using Statistics
using MIRPLib

const PREDICTIVE_EPS = 1.0e-9

function predictive_feature_names()
    return [
        "prefix_cost",
        "call_count",
        "remaining_horizon",
        "next_violation_urgency",
        "min_inventory_slack",
        "mean_inventory_slack",
        "vessel_utilization",
        "vessel_time_spread",
        "port_imbalance",
        "feasible_arc_ratio",
        "unique_port_ratio",
        "unique_vessel_ratio",
    ]
end

function normalized_port_slack(port::Port, inventory::Float64)
    capacity = max(Float64(port.capacity), PREDICTIVE_EPS)
    slack = port.type == :loading ? Float64(port.capacity) - inventory : inventory
    return clamp(slack / capacity, 0.0, 1.0)
end

function partial_solution_features(mirp::MIRP, solution::Solution)
    time_horizon = max(horizon(mirp), 1)
    call_count = length(solution.calls)
    prefix_cost = isfinite(solution.score) ? solution.score : 1.0e12

    next_violation = isempty(solution.port_next_violation) ? time_horizon + 1 : minimum(solution.port_next_violation)
    next_violation_urgency = next_violation > time_horizon ? 0.0 : (time_horizon + 1 - next_violation) / time_horizon

    min_inventory_slack = 1.0
    slack_sum = 0.0
    loading_fill_sum = 0.0
    unloading_fill_sum = 0.0
    loading_count = 0
    unloading_count = 0

    for port in mirp.ports
        inventory = solution.port_inventory[port.id]
        capacity = max(Float64(port.capacity), PREDICTIVE_EPS)
        slack = normalized_port_slack(port, inventory)
        min_inventory_slack = min(min_inventory_slack, slack)
        slack_sum += slack

        fill = clamp(inventory / capacity, 0.0, 1.0)
        if port.type == :loading
            loading_fill_sum += fill
            loading_count += 1
        else
            unloading_fill_sum += fill
            unloading_count += 1
        end
    end

    port_count = length(mirp.ports)
    mean_inventory_slack = port_count == 0 ? 1.0 : slack_sum / port_count
    mean_loading = loading_count == 0 ? 0.0 : loading_fill_sum / loading_count
    mean_unloading = unloading_count == 0 ? 0.0 : unloading_fill_sum / unloading_count
    port_imbalance = abs(mean_loading - mean_unloading)

    vessel_utilization_sum = 0.0
    for vessel in mirp.vessels
        vessel_utilization_sum += solution.vessel_inventory[vessel.id] /
            max(Float64(vessel.class.capacity), PREDICTIVE_EPS)
    end
    vessel_count = length(mirp.vessels)
    vessel_utilization = vessel_count == 0 ? 0.0 : vessel_utilization_sum / vessel_count

    min_vessel_time = isempty(solution.vessel_time) ? 0 : minimum(solution.vessel_time)
    max_vessel_time = isempty(solution.vessel_time) ? 0 : maximum(solution.vessel_time)
    vessel_time_spread = (max_vessel_time - min_vessel_time) / time_horizon
    remaining_horizon = max(0.0, (time_horizon - max_vessel_time) / time_horizon)

    feasible_arcs = 0
    for port in mirp.ports
        for vessel in mirp.vessels
            feasible_arcs += is_feasible(solution, port, vessel) ? 1 : 0
        end
    end
    total_arcs = max(port_count * vessel_count, 1)
    feasible_arc_ratio = feasible_arcs / total_arcs

    seen_ports = falses(port_count)
    seen_vessels = falses(vessel_count)
    unique_ports = 0
    unique_vessels = 0
    for call in solution.calls
        if 1 <= call.port.id <= port_count && !seen_ports[call.port.id]
            seen_ports[call.port.id] = true
            unique_ports += 1
        end
        if 1 <= call.vessel.id <= vessel_count && !seen_vessels[call.vessel.id]
            seen_vessels[call.vessel.id] = true
            unique_vessels += 1
        end
    end
    unique_port_ratio = unique_ports / max(port_count, 1)
    unique_vessel_ratio = unique_vessels / max(vessel_count, 1)

    return [
        prefix_cost,
        Float64(call_count),
        remaining_horizon,
        next_violation_urgency,
        min_inventory_slack,
        mean_inventory_slack,
        vessel_utilization,
        vessel_time_spread,
        port_imbalance,
        feasible_arc_ratio,
        unique_port_ratio,
        unique_vessel_ratio,
    ]
end

function heuristic_quality_estimate(mirp::MIRP, solution::Solution)
    time_horizon = max(horizon(mirp), 1)
    prefix_cost = isfinite(solution.score) ? solution.score : 1.0e12
    urgency_penalty = 0.0

    for port in mirp.ports
        next_violation = solution.port_next_violation[port.id]
        if next_violation <= time_horizon
            urgency = (time_horizon + 1 - next_violation) / time_horizon
            urgency_penalty += urgency * violation_price(mirp, port, next_violation)
        end
    end

    return prefix_cost + urgency_penalty
end
