function initial_port_next_violation(mirp::MIRP)
    time_horizon = horizon(mirp)
    return Int64[
        next_violation_period(port, Float64(port.inventory), 0, time_horizon) for port in mirp.ports
    ]
end

function load_after_call(call::Call)
    return call.port.type == :loading ? Float64(call.vessel.class.capacity) : 0.0
end

mutable struct CallEvaluator
    vessel_last_port::Vector{Port}
    vessel_has_call::Vector{Bool}
    last_occ_ports::Vector{Union{Nothing, Call}}
    last_occ_vessels::Vector{Union{Nothing, Call}}
    vessel_inventory::Vector{Float64}
    vessel_time::Vector{Int64}
    port_inventory::Vector{Float64}
    port_time::Vector{Int64}
    port_next_violation::Vector{Int64}
    berth_use::Vector{Dict{Int64, Int64}}
    routing_cost::Float64
    inventory_cost::Float64
    feasible::Bool
end

function CallEvaluator(mirp::MIRP)
    return CallEvaluator(
        Port[vessel.initial_port for vessel in mirp.vessels],
        falses(length(mirp.vessels)),
        Union{Nothing, Call}[nothing for _ in mirp.ports],
        Union{Nothing, Call}[nothing for _ in mirp.vessels],
        Float64[vessel.inventory for vessel in mirp.vessels],
        Int64[vessel.first_time for vessel in mirp.vessels],
        Float64[port.inventory for port in mirp.ports],
        zeros(Int64, length(mirp.ports)),
        initial_port_next_violation(mirp),
        [Dict{Int64, Int64}() for _ in mirp.ports],
        0.0,
        0.0,
        true,
    )
end

function clear_berth_use!(evaluator::CallEvaluator)
    for berth_use in evaluator.berth_use
        empty!(berth_use)
    end
    return evaluator
end

"""
Resets the evaluator to the initial state of the instance
"""
function reset_evaluator_to_initial!(evaluator::CallEvaluator, mirp::MIRP)
    for vessel in mirp.vessels
        vessel_id = vessel.id
        evaluator.vessel_last_port[vessel_id] = vessel.initial_port
        evaluator.vessel_has_call[vessel_id] = false
        evaluator.last_occ_vessels[vessel_id] = nothing
        evaluator.vessel_inventory[vessel_id] = vessel.inventory
        evaluator.vessel_time[vessel_id] = vessel.first_time
    end

    time_horizon = horizon(mirp)
    for port in mirp.ports
        port_id = port.id
        evaluator.last_occ_ports[port_id] = nothing
        evaluator.port_inventory[port_id] = port.inventory
        evaluator.port_time[port_id] = 0
        evaluator.port_next_violation[port_id] = next_violation_period(port, Float64(port.inventory), 0, time_horizon)
    end

    clear_berth_use!(evaluator)
    evaluator.routing_cost = 0.0
    evaluator.inventory_cost = 0.0
    evaluator.feasible = true
    return evaluator
end

"""
Resets the evaluator to the state of the solution up to the prefix_length call(including)
"""
function reset_evaluator_to_prefix!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64,
)
    reset_evaluator_to_initial!(evaluator, mirp)
    prefix_length <= 0 && return evaluator

    for call in @view solution.calls[1:prefix_length]
        port_id = call.port.id
        vessel_id = call.vessel.id
        evaluator.vessel_last_port[vessel_id] = call.port
        evaluator.vessel_has_call[vessel_id] = true
        evaluator.last_occ_vessels[vessel_id] = call
        evaluator.vessel_inventory[vessel_id] = load_after_call(call)
        evaluator.vessel_time[vessel_id] = call.service_time_port
        evaluator.last_occ_ports[port_id] = call
        evaluator.port_inventory[port_id] = call.inventory_level
        evaluator.port_time[port_id] = call.service_time_port
        evaluator.port_next_violation[port_id] = call.next_violation_time
        evaluator.berth_use[port_id][call.service_time_port] = call.num_vessels_in_port
    end

    last_prefix_call = solution.calls[prefix_length]
    evaluator.routing_cost = last_prefix_call.acc_routing_costs
    evaluator.inventory_cost = last_prefix_call.acc_inventory_costs
    return evaluator
end

"""
Returns if the ports are different type using evaluator
"""
function is_feasible_using_evaluator(evaluator::CallEvaluator, port::Port, vessel::Vessel)
    vessel_id = vessel.id
    last_port = evaluator.vessel_last_port[vessel_id]
    if !evaluator.vessel_has_call[vessel_id] && last_port.id == port.id
        return true
    end
    return last_port.type != port.type
end

function first_service_time_evaluator(
    mirp::MIRP,
    evaluator::CallEvaluator,
    port::Port,
    vessel::Vessel,
    arrival::Int64,
)
    port_id = port.id
    inventory_start = evaluator.port_inventory[port_id]
    from_t = evaluator.port_time[port_id]
    cargo = evaluator.vessel_inventory[vessel.id]
    time_horizon = horizon(mirp)
    berth_use = evaluator.berth_use[port_id]

    for t in max(1, arrival, from_t):time_horizon
        vessels_in_port = get(berth_use, t, 0)
        vessels_in_port >= port.berth_limit && continue

        inventory_at_t, _ = advance_inventory(mirp, port, inventory_start, from_t, t - 1)
        include_period_rate = t > from_t
        if service_is_inventory_feasible(mirp, port, vessel, inventory_at_t, cargo, t, include_period_rate)
            return t, vessels_in_port + 1
        end
    end

    return time_horizon + 1, 0
end

function evaluate_call!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    port::Port,
    vessel::Vessel,
)
    if !is_feasible_using_evaluator(evaluator, port, vessel)
        evaluator.feasible = false
        return :infeasible
    end

    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    from_port = evaluator.vessel_last_port[vessel_id]
    arrival = max(1, evaluator.vessel_time[vessel_id] + vessel.class.travel_times[from_port.id, port_id])
    service_time, vessels_in_port = first_service_time_evaluator(mirp, evaluator, port, vessel, arrival)
    service_time > time_horizon && return :discarded

    inventory, penalty = advance_inventory(
        mirp,
        port,
        evaluator.port_inventory[port_id],
        evaluator.port_time[port_id],
        service_time - 1,
    )
    evaluator.port_inventory[port_id] = inventory
    evaluator.inventory_cost += penalty

    cargo_before = evaluator.vessel_inventory[vessel_id]
    evaluator.routing_cost += route_cost(mirp, vessel, from_port, port, cargo_before)
    include_period_rate = service_time > evaluator.port_time[port_id]
    inventory_after, cargo_after, service_penalty = service_after_call(
        mirp,
        port,
        vessel,
        evaluator.port_inventory[port_id],
        cargo_before,
        service_time,
        include_period_rate,
    )
    evaluator.inventory_cost += service_penalty

    evaluator.port_inventory[port_id] = inventory_after
    evaluator.vessel_inventory[vessel_id] = cargo_after
    evaluator.port_time[port_id] = service_time
    evaluator.port_next_violation[port_id] = next_violation_period(port, inventory_after, service_time, time_horizon)
    evaluator.vessel_last_port[vessel_id] = port
    evaluator.vessel_has_call[vessel_id] = true
    evaluator.vessel_time[vessel_id] = service_time
    evaluator.berth_use[port_id][service_time] = vessels_in_port
    evaluator.feasible = true
    return :fulfilled
end

function final_evaluate_score(evaluator::CallEvaluator, mirp::MIRP)
    routing_cost = evaluator.routing_cost
    inventory_cost = evaluator.inventory_cost
    time_horizon = horizon(mirp)

    for port in mirp.ports
        _, penalty = advance_inventory(
            mirp,
            port,
            evaluator.port_inventory[port.id],
            evaluator.port_time[port.id],
            time_horizon,
        )
        inventory_cost += penalty
    end

    for vessel in mirp.vessels
        routing_cost -= mirp.metadata.reward_finishing_early * max(0, time_horizon - evaluator.vessel_time[vessel.id])
    end

    return routing_cost + inventory_cost
end
