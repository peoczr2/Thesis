function has_evaluated_calls(solution::Solution)
    return all(call -> call.service_time_port > 0, solution.calls)
end

function neighbor_source_solution(mirp::MIRP, solution::Solution)
    return solution.feasible && has_evaluated_calls(solution) ?
        solution :
        evaluate_solution!(mirp, clone_solution(mirp, solution); add_final_inventory_cost = true)
end

function initial_port_next_violation(mirp::MIRP)
    time_horizon = horizon(mirp)
    return Int64[
        next_violation_period(port, Float64(port.inventory), 0, time_horizon) for port in mirp.ports
    ]
end

function cargo_after_call(call::Call)
    return call.port.type == :loading ? Float64(call.vessel.class.capacity) : 0.0
end

function clone_evaluated_prefix(mirp::MIRP, solution::Solution, prefix_length::Int64)
    calls = Call[]
    sizehint!(calls, prefix_length)

    last_occ_ports = Union{Nothing, Call}[nothing for _ in mirp.ports]
    last_occ_vessels = Union{Nothing, Call}[nothing for _ in mirp.vessels]
    vessel_inventory = Float64[vessel.inventory for vessel in mirp.vessels]
    vessel_time = Int64[vessel.first_time for vessel in mirp.vessels]
    port_inventory = Float64[port.inventory for port in mirp.ports]
    port_time = zeros(Int64, length(mirp.ports))
    port_next_violation = initial_port_next_violation(mirp)

    for old_call in @view solution.calls[1:prefix_length]
        call = copy_evaluated_call(old_call)
        port_id = call.port.id
        vessel_id = call.vessel.id

        call.last_occ_port = last_occ_ports[port_id]
        call.last_occ_vessel = last_occ_vessels[vessel_id]
        if call.last_occ_port !== nothing
            call.last_occ_port.next_occ_port = call
        end
        if call.last_occ_vessel !== nothing
            call.last_occ_vessel.next_occ_vessel = call
        end

        push!(calls, call)
        last_occ_ports[port_id] = call
        last_occ_vessels[vessel_id] = call
        vessel_inventory[vessel_id] = cargo_after_call(call)
        vessel_time[vessel_id] = call.service_time_port
        port_inventory[port_id] = call.inventory_level
        port_time[port_id] = call.service_time_port
        port_next_violation[port_id] = call.next_violation_time
    end

    score = isempty(calls) ? 0.0 : calls[end].acc_total_costs
    return Solution(
        calls,
        score,
        last_occ_ports,
        last_occ_vessels,
        vessel_inventory,
        vessel_time,
        port_inventory,
        port_time,
        port_next_violation,
        true,
    )
end

function berth_use_by_port(mirp::MIRP, solution::Solution)
    berth_use = [Dict{Int64, Int64}() for _ in mirp.ports]
    for call in solution.calls
        if call.service_time_port > 0
            port_id = call.port.id
            service_time = call.service_time_port
            berth_use[port_id][service_time] = get(berth_use[port_id], service_time, 0) + 1
        end
    end
    return berth_use
end

function append_replayed_call!(mirp::MIRP, solution::Solution, call::Call, berth_use)
    port_id = call.port.id
    candidate = candidate_append(mirp, solution, call.port, call.vessel, berth_use[port_id])
    if candidate === nothing
        solution.feasible = false
        solution.score = Inf
        return false
    end

    append_evaluated_call!(mirp, solution, candidate)
    berth_use[port_id][candidate.service_time] = candidate.vessels_in_port
    return true
end

function add_final_inventory_cost!(mirp::MIRP, solution::Solution)
    routing_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_routing_costs
    inventory_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_inventory_costs
    time_horizon = horizon(mirp)

    for port in mirp.ports
        inventory, penalty = advance_inventory(
            mirp,
            port,
            solution.port_inventory[port.id],
            solution.port_time[port.id],
            time_horizon,
        )
        solution.port_inventory[port.id] = inventory
        solution.port_time[port.id] = time_horizon
        solution.port_next_violation[port.id] = time_horizon + 1
        inventory_cost += penalty
    end

    routing_cost -= early_finish_reward(mirp, solution)
    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end

function evaluate_suffix_neighbor(
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64,
    suffix_calls;
    add_final_inventory_cost::Bool = true,
)
    candidate = clone_evaluated_prefix(mirp, solution, prefix_length)
    berth_use = berth_use_by_port(mirp, candidate)

    for call in suffix_calls
        append_replayed_call!(mirp, candidate, call, berth_use) || return nothing
    end

    add_final_inventory_cost && add_final_inventory_cost!(mirp, candidate)
    return candidate.feasible && isfinite(candidate.score) ? candidate : nothing
end

function suffix_from_order(order::Vector{Call}, prefix_length::Int64)
    suffix = Call[]
    sizehint!(suffix, length(order) - prefix_length)
    for k in (prefix_length + 1):length(order)
        push!(suffix, order[k])
    end
    return suffix
end

function evaluate_swap(mirp::MIRP, solution::Solution, i::Int64, j::Int64)
    prefix_length = i - 1
    suffix = Call[]
    sizehint!(suffix, length(solution.calls) - prefix_length)

    for k in i:length(solution.calls)
        if k == i
            push!(suffix, solution.calls[j])
        elseif k == j
            push!(suffix, solution.calls[i])
        else
            push!(suffix, solution.calls[k])
        end
    end

    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix)
end

function evaluate_relocate(mirp::MIRP, solution::Solution, i::Int64, j::Int64)
    order = copy(solution.calls)
    call = splice!(order, i)
    insert!(order, j, call)
    prefix_length = min(i, j) - 1
    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix_from_order(order, prefix_length))
end

function evaluate_replace(mirp::MIRP, solution::Solution, i::Int64, port::Port)
    prefix_length = i - 1
    suffix = Call[]
    sizehint!(suffix, length(solution.calls) - prefix_length)
    old_call = solution.calls[i]
    push!(suffix, Call(port, old_call.vessel))

    for k in (i + 1):length(solution.calls)
        push!(suffix, solution.calls[k])
    end

    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix)
end

function evaluate_insert(mirp::MIRP, solution::Solution, first_port::Port, vessel::Vessel, second_port::Port)
    prefix_length = length(solution.calls)
    suffix = [Call(first_port, vessel), Call(second_port, vessel)]
    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix)
end

function evaluate_remove(mirp::MIRP, solution::Solution, first_index::Int64, second_index::Union{Nothing, Int64} = nothing)
    prefix_length = first_index - 1
    suffix = Call[]
    sizehint!(suffix, length(solution.calls) - prefix_length - 1 - (second_index === nothing ? 0 : 1))

    for k in first_index:length(solution.calls)
        if k == first_index || k == second_index
            continue
        end
        push!(suffix, solution.calls[k])
    end

    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix)
end

function evaluate_swap_port(mirp::MIRP, solution::Solution, i::Int64, j::Int64)
    prefix_length = i - 1
    suffix = Call[]
    sizehint!(suffix, length(solution.calls) - prefix_length)
    call_i = solution.calls[i]
    call_j = solution.calls[j]

    for k in i:length(solution.calls)
        if k == i
            push!(suffix, Call(call_j.port, call_i.vessel))
        elseif k == j
            push!(suffix, Call(call_i.port, call_j.vessel))
        else
            push!(suffix, solution.calls[k])
        end
    end

    return evaluate_suffix_neighbor(mirp, solution, prefix_length, suffix)
end
