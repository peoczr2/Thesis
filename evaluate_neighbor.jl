function has_evaluated_calls(solution::Solution)
    return all(call -> call.service_time_port > 0, solution.calls)
end

# TODO: this is kind of useless
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
    if !is_feasible(solution, call.port, call.vessel)
        solution.feasible = false
        solution.score = Inf
        return :infeasible
    end

    port_id = call.port.id
    candidate = candidate_append(mirp, solution, call.port, call.vessel, berth_use[port_id])
    if candidate === nothing
        return :truncated
    end

    append_evaluated_call!(mirp, solution, candidate)
    berth_use[port_id][candidate.service_time] = candidate.vessels_in_port
    return :appended
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


"""
Call evaluator that holds every information to efficiently iterate forward through a solution call by call and evaluate it
"""
mutable struct CallEvaluator
    vessel_last_port::Vector{Port}
    vessel_has_call::Vector{Bool}
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

function reset_evaluator_to_initial!(evaluator::CallEvaluator, mirp::MIRP)
    for vessel in mirp.vessels
        vessel_id = vessel.id
        evaluator.vessel_last_port[vessel_id] = vessel.initial_port
        evaluator.vessel_has_call[vessel_id] = false
        evaluator.vessel_inventory[vessel_id] = vessel.inventory
        evaluator.vessel_time[vessel_id] = vessel.first_time
    end

    time_horizon = horizon(mirp)
    for port in mirp.ports
        port_id = port.id
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
        evaluator.vessel_inventory[vessel_id] = cargo_after_call(call)
        evaluator.vessel_time[vessel_id] = call.service_time_port
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

function replay_is_feasible(evaluator::CallEvaluator, port::Port, vessel::Vessel)
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
    replay_is_feasible(evaluator, port, vessel) || return :infeasible

    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    from_port = evaluator.vessel_last_port[vessel_id]
    last_service_time_vessel = evaluator.vessel_time[vessel_id]
    arrival = max(1, last_service_time_vessel + vessel.class.travel_times[from_port.id, port_id])
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
    rate = include_period_rate ? port.rates[period_index(port.rates, service_time)] : 0.0

    if port.type == :loading
        load_amount = max(0.0, vessel.class.capacity - cargo_before)
        inventory_after = evaluator.port_inventory[port_id] + rate - load_amount
        cargo_after = cargo_before + load_amount
        if inventory_after < 0.0
            evaluator.inventory_cost += -inventory_after * violation_price(mirp, port, service_time)
            inventory_after = 0.0
        end
        evaluator.port_inventory[port_id] = inventory_after
        evaluator.vessel_inventory[vessel_id] = cargo_after
    else
        unload_amount = cargo_before
        inventory_after = evaluator.port_inventory[port_id] - rate + unload_amount
        if inventory_after > port.capacity
            evaluator.inventory_cost += (inventory_after - port.capacity) * violation_price(mirp, port, service_time)
            inventory_after = Float64(port.capacity)
        end
        evaluator.port_inventory[port_id] = inventory_after
        evaluator.vessel_inventory[vessel_id] = 0.0
    end

    evaluator.port_time[port_id] = service_time
    evaluator.port_next_violation[port_id] = next_violation_period(port, evaluator.port_inventory[port_id], service_time, time_horizon)
    evaluator.vessel_last_port[vessel_id] = port
    evaluator.vessel_has_call[vessel_id] = true
    evaluator.vessel_time[vessel_id] = service_time
    evaluator.berth_use[port_id][service_time] = vessels_in_port
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

"""
Scores the neighbor. Return score=Inf if the change is infeasible.
Does not modify solution.
"""
function score_swap!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    for k in i:length(solution.calls)
        call = k == i ? solution.calls[j] : k == j ? solution.calls[i] : solution.calls[k]
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function relocated_call_at(calls::Vector{Call}, i::Int64, j::Int64, k::Int64)
    if i < j
        if k < i || k > j
            return calls[k]
        elseif k == j
            return calls[i]
        else
            return calls[k + 1]
        end
    else
        if k < j || k > i
            return calls[k]
        elseif k == j
            return calls[i]
        else
            return calls[k - 1]
        end
    end
end

function score_relocate!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    prefix_length = min(i, j) - 1
    reset_evaluator_to_prefix!(evaluator, mirp, solution, prefix_length)
    for k in (prefix_length + 1):length(solution.calls)
        call = relocated_call_at(solution.calls, i, j, k)
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_replace!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    port::Port,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    old_call = solution.calls[i]
    status = evaluate_call!(evaluator, mirp, port, old_call.vessel)
    status === :infeasible && return Inf
    if status !== :discarded
        for k in (i + 1):length(solution.calls)
            call = solution.calls[k]
            status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
            status === :fulfilled && continue
            status === :discarded && break
            return Inf
        end
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_insert!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    first_port::Port,
    vessel::Vessel,
    second_port::Port,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, length(solution.calls))
    status = evaluate_call!(evaluator, mirp, first_port, vessel)
    status === :infeasible && return Inf
    status === :discarded && return Inf
    status = evaluate_call!(evaluator, mirp, second_port, vessel)
    status === :infeasible && return Inf
    return final_evaluate_score(evaluator, mirp)
end

function score_remove!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    first_index::Int64,
    second_index::Union{Nothing, Int64} = nothing,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, first_index - 1)
    for k in first_index:length(solution.calls)
        (k == first_index || k == second_index) && continue
        call = solution.calls[k]
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_swap_port!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    call_i = solution.calls[i]
    call_j = solution.calls[j]
    for k in i:length(solution.calls)
        if k == i
            port, vessel = call_j.port, call_i.vessel
        elseif k == j
            port, vessel = call_i.port, call_j.vessel
        else
            call = solution.calls[k]
            port, vessel = call.port, call.vessel
        end
        status = evaluate_call!(evaluator, mirp, port, vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end


"""
Modifies the solution by evaluating the calls from a certain index to the end, and returns the modified solution.
"""
function evaluate_suffix_neighbor!(
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64,
    suffix_calls;
    add_final_inventory_cost::Bool = true,
) # TODO: this function should not make a hard copy of the solution and should assume that the solution is correctly evaluated up to the prefix index call
    candidate = clone_evaluated_prefix(mirp, solution, prefix_length)
    berth_use = berth_use_by_port(mirp, candidate)

    for call in suffix_calls
        replay_status = append_replayed_call!(mirp, candidate, call, berth_use)
        replay_status === :appended && continue
        replay_status === :truncated && break
        return nothing
    end

    add_final_inventory_cost && add_final_inventory_cost!(mirp, candidate)
    return candidate.feasible && isfinite(candidate.score) ? candidate : nothing
end

function evaluate_suffix_neighbor!(
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64;
    add_final_inventory_cost::Bool = true,
)
    suffix_calls = suffix_from_order(solution.calls, prefix_length)
    return evaluate_suffix_neighbor!(
        mirp,
        solution,
        prefix_length,
        suffix_calls;
        add_final_inventory_cost = add_final_inventory_cost,
    )
end

function evaluate_suffix_neighbor(
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64,
    suffix_calls;
    add_final_inventory_cost::Bool = true,
)
    return evaluate_suffix_neighbor!(
        mirp,
        solution,
        prefix_length,
        suffix_calls;
        add_final_inventory_cost = add_final_inventory_cost,
    )
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
    # TODO: could be like instead of returning a hard copy it could return only the final score, that was calculated by starting from i-1 accepting as it was evaled then go until j-1 keep in mind that j changed then go until the end. And the eval is basically just keeping track of the current state not for all eval and not overriding the solution. 
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
