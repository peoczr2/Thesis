
using Random
using MIRPLib

"""
Solves floating point inaccuracy issues when comparing
"""
const EPS = 1.0e-9

function horizon(mirp::MIRP)
    return mirp.metadata.n_periods
end

# TODO: i mean is this neccessary
function period_index(values::AbstractVector, t::Int64)
    return clamp(t, 1, length(values))
end

# TODO: i dont know, could tweak it
function violation_price(mirp::MIRP, port::Port, t::Int64)
    price = port.prices[period_index(port.prices, t)]
    return price == 0.0 ? mirp.metadata.spot_market_price : price
end

function clear_call_state!(call::Call)
    call.last_occ_vessel = nothing
    call.last_occ_port = nothing
    call.next_occ_vessel = nothing
    call.next_occ_port = nothing
    call.last_service_time_vessel = 0
    call.service_time_port = 0
    call.num_vessels_in_port = 0
    call.inventory_level = 0.0
    call.next_violation_time = typemax(Int64)
    call.acc_routing_costs = 0.0
    call.acc_inventory_costs = 0.0
    call.acc_total_costs = 0.0
    return call
end

function reset_solution_state!(solution::Solution, mirp::MIRP)
    time_horizon = horizon(mirp)
    solution.score = Inf
    solution.last_occ_ports = Union{Nothing, Call}[nothing for _ in mirp.ports]
    solution.last_occ_vessels = Union{Nothing, Call}[nothing for _ in mirp.vessels]
    solution.vessel_inventory = Float64[vessel.inventory for vessel in mirp.vessels]
    solution.vessel_time = Int64[vessel.first_time for vessel in mirp.vessels]
    solution.port_inventory = Float64[port.inventory for port in mirp.ports]
    solution.port_time = zeros(Int64, length(mirp.ports))
    solution.port_next_violation = Int64[
        next_violation_period(port, Float64(port.inventory), 0, time_horizon) for port in mirp.ports
    ]
    solution.feasible = true

    for call in solution.calls
        clear_call_state!(call)
    end

    return solution
end

function advance_inventory(mirp::MIRP, port::Port, inventory::Float64, from_t::Int64, to_t::Int64)
    penalty = 0.0

    if to_t <= from_t
        return inventory, penalty
    end

    for t in (from_t + 1):to_t
        rate = port.rates[period_index(port.rates, t)]

        if port.type == :loading
            inventory += rate
            if inventory > port.capacity
                excess = inventory - port.capacity
                penalty += excess * violation_price(mirp, port, t)
                inventory = Float64(port.capacity)
            end
        else
            inventory -= rate
            if inventory < 0.0
                shortage = -inventory
                penalty += shortage * violation_price(mirp, port, t)
                inventory = 0.0
            end
        end
    end

    return inventory, penalty
end

function next_violation_period(port::Port, inventory::Float64, from_t::Int64, time_horizon::Int64)
    if from_t >= time_horizon
        return time_horizon + 1
    end

    for t in (from_t + 1):time_horizon
        rate = port.rates[period_index(port.rates, t)]
        inventory += port.type == :loading ? rate : -rate

        if inventory > port.capacity || inventory < 0.0
            return t
        end
    end

    return time_horizon + 1
end



"""
Checks if the vessels last port and the port param has different types.
"""
function is_feasible(node::Solution, port::Port, vessel::Vessel)
    last_call = node.last_occ_vessels[vessel.id]
    last_port = last_call === nothing ? vessel.initial_port : last_call.port # TODO: how to handle when a vessel has not yet visited any port

    if last_call === nothing && last_port.id == port.id
        return true
    end

    return last_port.type != port.type
end

struct AppendCandidate
    port::Port
    vessel::Vessel
    arrival_time::Int64
    service_time::Int64
    vessels_in_port::Int64
end

function inventory_after_service_period(
    mirp::MIRP,
    port::Port,
    vessel::Vessel,
    inventory::Float64,
    cargo::Float64,
    service_time::Int64,
    include_period_rate::Bool = true,
)
    rate = include_period_rate ? port.rates[period_index(port.rates, service_time)] : 0.0

    if port.type == :loading
        load_amount = max(0.0, vessel.class.capacity - cargo)
        return inventory + rate - load_amount
    end

    unload_amount = cargo
    return inventory - rate + unload_amount
end

function inventory_after_service_period(
    mirp::MIRP,
    call::Call,
    inventory::Float64,
    cargo::Float64,
    service_time::Int64,
    include_period_rate::Bool = true,
)
    return inventory_after_service_period(mirp, call.port, call.vessel, inventory, cargo, service_time, include_period_rate)
end

# TODO: i think there is no such a thing as inventory_feasibility, as the heuristic should actively seek a service_time where there is enough inventory or enough free capacity
function service_is_inventory_feasible(
    mirp::MIRP,
    port::Port,
    vessel::Vessel,
    inventory::Float64,
    cargo::Float64,
    service_time::Int64,
    include_period_rate::Bool = true,
)
    inventory_after = inventory_after_service_period(mirp, port, vessel, inventory, cargo, service_time, include_period_rate)
    return 0.0 - EPS <= inventory_after <= port.capacity + EPS
end

function service_is_inventory_feasible(mirp::MIRP, call::Call, inventory::Float64, cargo::Float64, service_time::Int64)
    return service_is_inventory_feasible(mirp, call.port, call.vessel, inventory, cargo, service_time)
end

function first_service_time(
    mirp::MIRP,
    solution::Solution,
    port::Port,
    vessel::Vessel,
    berth_use::Dict{Int64, Int64},
    arrival::Int64,
    time_horizon::Int64,
)
    port_id = port.id
    inventory_start = solution.port_inventory[port_id]
    from_t = solution.port_time[port_id]
    cargo = solution.vessel_inventory[vessel.id]

    for t in max(1, arrival, from_t):time_horizon
        vessels_in_port = get(berth_use, t, 0)
        if vessels_in_port >= port.berth_limit
            continue
        end

        inventory_at_t, _ = advance_inventory(mirp, port, inventory_start, from_t, t - 1)
        include_period_rate = t > from_t
        if service_is_inventory_feasible(mirp, port, vessel, inventory_at_t, cargo, t, include_period_rate)
            return t, vessels_in_port + 1
        end
    end

    return time_horizon + 1, 0
end

function first_service_time(
    mirp::MIRP,
    solution::Solution,
    call::Call,
    berth_use::Dict{Int64, Int64},
    arrival::Int64,
    time_horizon::Int64,
)
    return first_service_time(mirp, solution, call.port, call.vessel, berth_use, arrival, time_horizon)
end

# TODO: check this
function route_cost(mirp::MIRP, vessel::Vessel, from_port::Port, to_port::Port, cargo_before::Float64)
    travel_cost = mirp.distances[from_port.id, to_port.id] * vessel.class.travel_cost_km

    if from_port.type == :unloading && to_port.type == :loading && cargo_before <= EPS
        travel_cost *= max(0.0, 1.0 - vessel.class.discount_empty)
    end

    return travel_cost + to_port.fee
end

function early_finish_reward(mirp::MIRP, solution::Solution)
    time_horizon = horizon(mirp)
    reward = 0.0

    for vessel in mirp.vessels
        last_call = solution.last_occ_vessels[vessel.id]
        finish_time = last_call === nothing ? vessel.first_time : last_call.service_time_port
        reward += mirp.metadata.reward_finishing_early * max(0, time_horizon - finish_time)
    end

    return reward
end

function apply_service!(mirp::MIRP, solution::Solution, call::Call, service_time::Int64)
    port_id = call.port.id
    vessel_id = call.vessel.id
    inventory = solution.port_inventory[port_id]
    cargo = solution.vessel_inventory[vessel_id]
    include_period_rate = service_time > solution.port_time[port_id]
    penalty = 0.0

    if call.port.type == :loading
        load_amount = max(0.0, call.vessel.class.capacity - cargo)
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time, include_period_rate)
        cargo += load_amount

        if inventory < 0.0
            penalty += -inventory * violation_price(mirp, call.port, service_time)
            inventory = 0.0
        end
    else
        unload_amount = cargo
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time, include_period_rate)
        cargo = 0.0

        if inventory > call.port.capacity
            penalty += (inventory - call.port.capacity) * violation_price(mirp, call.port, service_time)
            inventory = Float64(call.port.capacity)
        end
    end

    solution.port_inventory[port_id] = inventory
    solution.vessel_inventory[vessel_id] = cargo
    return penalty
end

function berth_use_for_port(solution::Solution, port_id::Int64)
    return berth_use_for_port(solution, port_id, length(solution.calls))
end

function berth_use_for_port(solution::Solution, port_id::Int64, prefix_length::Int64)
    berth_use = Dict{Int64, Int64}()
    for i in 1:prefix_length
        existing_call = solution.calls[i]
        if existing_call.port.id == port_id && existing_call.service_time_port > 0
            service_time = existing_call.service_time_port
            berth_use[service_time] = get(berth_use, service_time, 0) + 1
        end
    end

    return berth_use
end

function candidate_append(mirp::MIRP, solution::Solution, port::Port, vessel::Vessel)
    return candidate_append(mirp, solution, port, vessel, berth_use_for_port(solution, port.id))
end

function candidate_append(
    mirp::MIRP,
    solution::Solution,
    port::Port,
    vessel::Vessel,
    berth_use::Dict{Int64, Int64},
)
    is_feasible(solution, port, vessel) || return nothing

    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    last_occ_vessel = solution.last_occ_vessels[vessel_id]
    from_port = last_occ_vessel === nothing ? vessel.initial_port : last_occ_vessel.port
    last_service_time_vessel = last_occ_vessel === nothing ? vessel.first_time : last_occ_vessel.service_time_port
    arrival = max(1, last_service_time_vessel + vessel.class.travel_times[from_port.id, port_id])

    service_time, vessels_in_port = first_service_time(
        mirp,
        solution,
        port,
        vessel,
        berth_use,
        arrival,
        time_horizon,
    )

    service_time > time_horizon && return nothing
    return AppendCandidate(port, vessel, arrival, service_time, vessels_in_port)
end

"""
After each call was evaluated in the solution this function handles the remaining parts.
Like the final inventory penalties, violations and early finish rewards.
"""
function finalize_evaluation!(mirp::MIRP, solution::Solution)
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


# TODO: try to make it useless
function reset_solution_to_evaluated_prefix!(mirp::MIRP, solution::Solution, prefix_length::Int64)
    time_horizon = horizon(mirp)
    solution.last_occ_ports = Union{Nothing, Call}[nothing for _ in mirp.ports]
    solution.last_occ_vessels = Union{Nothing, Call}[nothing for _ in mirp.vessels]
    solution.vessel_inventory = Float64[vessel.inventory for vessel in mirp.vessels]
    solution.vessel_time = Int64[vessel.first_time for vessel in mirp.vessels]
    solution.port_inventory = Float64[port.inventory for port in mirp.ports]
    solution.port_time = zeros(Int64, length(mirp.ports))
    solution.port_next_violation = Int64[
        next_violation_period(port, Float64(port.inventory), 0, time_horizon) for port in mirp.ports
    ]
    solution.score = 0.0
    solution.feasible = true

    for i in 1:prefix_length
        call = solution.calls[i]
        port_id = call.port.id
        vessel_id = call.vessel.id

        call.last_occ_port = solution.last_occ_ports[port_id]
        call.last_occ_vessel = solution.last_occ_vessels[vessel_id]
        call.next_occ_port = nothing
        call.next_occ_vessel = nothing
        if call.last_occ_port !== nothing
            call.last_occ_port.next_occ_port = call
        end
        if call.last_occ_vessel !== nothing
            call.last_occ_vessel.next_occ_vessel = call
        end

        solution.last_occ_ports[port_id] = call
        solution.last_occ_vessels[vessel_id] = call
        solution.vessel_inventory[vessel_id] = call.port.type == :loading ? Float64(call.vessel.class.capacity) : 0.0
        solution.vessel_time[vessel_id] = call.service_time_port
        solution.port_inventory[port_id] = call.inventory_level
        solution.port_time[port_id] = call.service_time_port
        solution.port_next_violation[port_id] = call.next_violation_time
        solution.score = call.acc_total_costs
    end

    return solution
end

"""
Modifies the solution by evaluating a call at a specific index in the solution.
"""
function evaluate_call_i!(mirp::MIRP, solution::Solution, evaluator::CallEvaluator, call_index::Int64)
    time_horizon = horizon(mirp)
    call = solution.calls[call_index]
    clear_call_state!(call)

    if !is_feasible(solution, call.port, call.vessel)
        solution.feasible = false
        solution.score = Inf
        return nothing
    end

    port_id = call.port.id
    vessel_id = call.vessel.id
    last_occ_vessel = solution.last_occ_vessels[vessel_id]
    last_occ_port = solution.last_occ_ports[port_id]
    from_port = last_occ_vessel === nothing ? call.vessel.initial_port : last_occ_vessel.port
    last_service_time_vessel = last_occ_vessel === nothing ? call.vessel.first_time : last_occ_vessel.service_time_port
    arrival = max(1, last_service_time_vessel + call.vessel.class.travel_times[from_port.id, port_id])
    berth_use = berth_use_for_port(solution, port_id, call_index - 1)
    service_time, vessels_in_port = first_service_time(
        mirp,
        solution,
        call,
        berth_use,
        arrival,
        time_horizon,
    )

    if service_time > time_horizon
        resize!(solution.calls, call_index - 1)
        solution.score = call_index == 1 ? 0.0 : solution.calls[call_index - 1].acc_total_costs
        return :discarded
    end

    routing_cost = call_index == 1 ? 0.0 : solution.calls[call_index - 1].acc_routing_costs
    inventory_cost = call_index == 1 ? 0.0 : solution.calls[call_index - 1].acc_inventory_costs
    inventory, penalty = advance_inventory(
        mirp,
        call.port,
        solution.port_inventory[port_id],
        solution.port_time[port_id],
        service_time - 1,
    )
    solution.port_inventory[port_id] = inventory
    inventory_cost += penalty

    cargo_before = solution.vessel_inventory[vessel_id]
    routing_cost += route_cost(mirp, call.vessel, from_port, call.port, cargo_before)
    inventory_cost += apply_service!(mirp, solution, call, service_time)

    call.last_occ_vessel = last_occ_vessel
    call.last_occ_port = last_occ_port
    if last_occ_vessel !== nothing
        last_occ_vessel.next_occ_vessel = call
    end
    if last_occ_port !== nothing
        last_occ_port.next_occ_port = call
    end

    call.last_service_time_vessel = last_service_time_vessel
    call.service_time_port = service_time
    call.num_vessels_in_port = vessels_in_port
    call.inventory_level = solution.port_inventory[port_id]
    call.next_violation_time = next_violation_period(call.port, call.inventory_level, service_time, time_horizon)
    solution.port_next_violation[port_id] = call.next_violation_time
    call.acc_routing_costs = routing_cost
    call.acc_inventory_costs = inventory_cost
    call.acc_total_costs = routing_cost + inventory_cost

    solution.last_occ_ports[port_id] = call
    solution.last_occ_vessels[vessel_id] = call
    solution.port_time[port_id] = service_time
    solution.vessel_time[vessel_id] = service_time
    solution.score = call.acc_total_costs
    solution.feasible = true
    return :fulfilled
end
function evaluate_call_i!(mirp::MIRP, solution::Solution, call_index::Int64)
    evaluator = CallEvaluator(mirp)
    return evaluate_call_i!(mirp, solution, evaluator, call_index)
end

"""
Append a known-feasible candidate to an evaluated solution, updating evaluator caches in place. It does not finalize the evaluation, thus final score is not calculated
"""
function append_evaluated_call!(mirp::MIRP, solution::Solution, candidate::AppendCandidate)
    port = candidate.port
    vessel = candidate.vessel
    call = Call(port, vessel)
    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    last_occ_vessel = solution.last_occ_vessels[vessel_id]
    last_occ_port = solution.last_occ_ports[port_id]
    from_port = last_occ_vessel === nothing ? vessel.initial_port : last_occ_vessel.port
    last_service_time_vessel = last_occ_vessel === nothing ? vessel.first_time : last_occ_vessel.service_time_port
    service_time = candidate.service_time
    vessels_in_port = candidate.vessels_in_port

    routing_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_routing_costs # TODO: maybe it could accept that its initialized with 0.0
    inventory_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_inventory_costs
    inventory, penalty = advance_inventory(
        mirp,
        port,
        solution.port_inventory[port_id],
        solution.port_time[port_id],
        service_time - 1,
    )
    solution.port_inventory[port_id] = inventory
    inventory_cost += penalty

    cargo_before = solution.vessel_inventory[vessel_id]
    routing_cost += route_cost(mirp, vessel, from_port, port, cargo_before)
    inventory_cost += apply_service!(mirp, solution, call, service_time)

    call.last_occ_vessel = last_occ_vessel
    call.last_occ_port = last_occ_port
    if last_occ_vessel !== nothing
        last_occ_vessel.next_occ_vessel = call
    end
    if last_occ_port !== nothing
        last_occ_port.next_occ_port = call
    end

    call.last_service_time_vessel = last_service_time_vessel
    call.service_time_port = service_time
    call.num_vessels_in_port = vessels_in_port
    call.inventory_level = solution.port_inventory[port_id]
    call.next_violation_time = next_violation_period(port, call.inventory_level, service_time, time_horizon)
    solution.port_next_violation[port_id] = call.next_violation_time
    call.acc_routing_costs = routing_cost
    call.acc_inventory_costs = inventory_cost
    call.acc_total_costs = routing_cost + inventory_cost

    push!(solution.calls, call)
    solution.last_occ_ports[port_id] = call
    solution.last_occ_vessels[vessel_id] = call
    solution.port_time[port_id] = service_time
    solution.vessel_time[vessel_id] = service_time
    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end

"""
Appends a call to a solution hard copy and evaluates this new solution efficiently. It does not finalize the evaluation, thus final score is not calculated
"""
function append_evaluated_call(mirp::MIRP, solution::Solution, port::Port, vessel::Vessel)
    new_solution = clone_evaluated_solution(mirp, solution)
    candidate = candidate_append(mirp, new_solution, port, vessel)

    if candidate === nothing
        call = Call(port, vessel)
        push!(new_solution.calls, call)
        new_solution.feasible = false
        new_solution.score = Inf
        return new_solution
    end

    return append_evaluated_call!(mirp, new_solution, candidate)
end

"""
Returns/Modifies the solution object, no hard-copy
"""
function evaluate_solution!(mirp::MIRP, solution::Solution; add_final_inventory_cost::Bool = true)
    reset_solution_state!(solution, mirp)

    time_horizon = horizon(mirp)
    berth_use = [Dict{Int64, Int64}() for _ in mirp.ports]
    routing_cost = 0.0
    inventory_cost = 0.0

    for (call_index, call) in enumerate(solution.calls)
        if !is_feasible(solution, call.port, call.vessel)
            solution.feasible = false
            solution.score = Inf
            return solution
        end

        port_id = call.port.id
        vessel_id = call.vessel.id
        last_occ_vessel = solution.last_occ_vessels[vessel_id]
        last_occ_port = solution.last_occ_ports[port_id]
        from_port = last_occ_vessel === nothing ? call.vessel.initial_port : last_occ_vessel.port
        last_service_time_vessel = last_occ_vessel === nothing ? call.vessel.first_time : last_occ_vessel.service_time_port
        arrival = max(1, last_service_time_vessel + call.vessel.class.travel_times[from_port.id, port_id])
        service_time, vessels_in_port = first_service_time(
            mirp,
            solution,
            call,
            berth_use[port_id],
            arrival,
            time_horizon,
        )

        if service_time > time_horizon
            resize!(solution.calls, call_index - 1)
            break
        end

        inventory, penalty = advance_inventory(
            mirp,
            call.port,
            solution.port_inventory[port_id],
            solution.port_time[port_id],
            service_time - 1,
        )
        solution.port_inventory[port_id] = inventory
        inventory_cost += penalty

        cargo_before = solution.vessel_inventory[vessel_id]
        routing_cost += route_cost(mirp, call.vessel, from_port, call.port, cargo_before)
        inventory_cost += apply_service!(mirp, solution, call, service_time)

        call.last_occ_vessel = last_occ_vessel
        call.last_occ_port = last_occ_port
        if last_occ_vessel !== nothing
            last_occ_vessel.next_occ_vessel = call
        end
        if last_occ_port !== nothing
            last_occ_port.next_occ_port = call
        end

        call.last_service_time_vessel = last_service_time_vessel
        call.service_time_port = service_time
        call.num_vessels_in_port = vessels_in_port
        call.inventory_level = solution.port_inventory[port_id]
        call.next_violation_time = next_violation_period(call.port, call.inventory_level, service_time, time_horizon)
        solution.port_next_violation[port_id] = call.next_violation_time
        call.acc_routing_costs = routing_cost
        call.acc_inventory_costs = inventory_cost
        call.acc_total_costs = routing_cost + inventory_cost

        solution.last_occ_ports[port_id] = call
        solution.last_occ_vessels[vessel_id] = call
        solution.port_time[port_id] = service_time
        solution.vessel_time[vessel_id] = service_time
        berth_use[port_id][service_time] = vessels_in_port
    end

    if add_final_inventory_cost
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
    end

    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end