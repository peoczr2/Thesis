using Random
using MIRPLib

const EPS = 1.0e-9

function horizon(mirp::MIRP)
    return mirp.metadata.n_periods
end

function period_index(values::AbstractVector, t::Int64)
    return clamp(t, 1, length(values))
end

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

# Evolve a port inventory between service times, charging spot-market penalties
# when stock violates the port lower or upper bound.
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

# Paper route compatibility: after leaving its initial position, a vessel must
# alternate between loading and unloading ports. Cargo is derived from that route.
function is_feasible(node::Solution, port::Port, vessel::Vessel)
    last_call = node.last_occ_vessels[vessel.id]
    last_port = last_call === nothing ? vessel.initial_port : last_call.port

    if last_call === nothing && last_port.id == port.id
        return true
    end

    return last_port.type != port.type
end

function inventory_after_service_period(mirp::MIRP, call::Call, inventory::Float64, cargo::Float64, service_time::Int64)
    rate = call.port.rates[period_index(call.port.rates, service_time)]

    if call.port.type == :loading
        load_amount = max(0.0, call.vessel.class.capacity - cargo)
        return inventory + rate - load_amount
    end

    unload_amount = cargo
    return inventory - rate + unload_amount
end

function service_is_inventory_feasible(mirp::MIRP, call::Call, inventory::Float64, cargo::Float64, service_time::Int64)
    inventory_after = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
    return 0.0 - EPS <= inventory_after <= call.port.capacity + EPS
end

# Search the first period where both berth capacity and service-period inventory
# balance allow this call to be scheduled.
function first_service_time(
    mirp::MIRP,
    solution::Solution,
    call::Call,
    berth_use::Dict{Int64, Int64},
    arrival::Int64,
    time_horizon::Int64,
)
    port_id = call.port.id
    inventory_start = solution.port_inventory[port_id]
    from_t = solution.port_time[port_id]
    cargo = solution.vessel_inventory[call.vessel.id]

    for t in max(1, arrival):time_horizon
        vessels_in_port = get(berth_use, t, 0)
        if vessels_in_port >= call.port.berth_limit
            continue
        end

        inventory_at_t, _ = advance_inventory(mirp, call.port, inventory_start, from_t, t - 1)
        if service_is_inventory_feasible(mirp, call, inventory_at_t, cargo, t)
            return t, vessels_in_port + 1
        end
    end

    return time_horizon + 1, 0
end

function route_cost(mirp::MIRP, vessel::Vessel, from_port::Port, to_port::Port, cargo_before::Float64)
    cost = mirp.distances[from_port.id, to_port.id] * vessel.class.travel_cost_km + to_port.fee

    if from_port.type == :unloading && to_port.type == :loading && cargo_before <= EPS
        cost *= max(0.0, 1.0 - vessel.class.discount_empty)
    end

    return cost
end

# Apply the load or unload operation in the service period after that period's
# port production/consumption has been accounted for.
function apply_service!(mirp::MIRP, solution::Solution, call::Call, service_time::Int64)
    port_id = call.port.id
    vessel_id = call.vessel.id
    inventory = solution.port_inventory[port_id]
    cargo = solution.vessel_inventory[vessel_id]
    penalty = 0.0

    if call.port.type == :loading
        load_amount = max(0.0, call.vessel.class.capacity - cargo)
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
        cargo += load_amount

        if inventory < 0.0
            penalty += -inventory * violation_price(mirp, call.port, service_time)
            inventory = 0.0
        end
    else
        unload_amount = cargo
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
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

function append_evaluated_call(mirp::MIRP, solution::Solution, port::Port, vessel::Vessel)
    new_solution = clone_evaluated_solution(mirp, solution)
    call = Call(port, vessel)

    if !is_feasible(new_solution, port, vessel)
        push!(new_solution.calls, call)
        new_solution.feasible = false
        new_solution.score = Inf
        return new_solution
    end

    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    last_occ_vessel = new_solution.last_occ_vessels[vessel_id]
    last_occ_port = new_solution.last_occ_ports[port_id]
    from_port = last_occ_vessel === nothing ? vessel.initial_port : last_occ_vessel.port
    last_service_time_vessel = last_occ_vessel === nothing ? vessel.first_time : last_occ_vessel.service_time_port
    arrival = max(1, last_service_time_vessel + vessel.class.travel_times[from_port.id, port_id])

    berth_use = Dict{Int64, Int64}()
    for existing_call in new_solution.calls
        if existing_call.port.id == port_id && existing_call.service_time_port > 0
            berth_use[existing_call.service_time_port] = get(berth_use, existing_call.service_time_port, 0) + 1
        end
    end

    service_time, vessels_in_port = first_service_time(
        mirp,
        new_solution,
        call,
        berth_use,
        arrival,
        time_horizon,
    )

    if service_time > time_horizon
        push!(new_solution.calls, call)
        new_solution.feasible = false
        new_solution.score = Inf
        return new_solution
    end

    routing_cost = isempty(new_solution.calls) ? 0.0 : new_solution.calls[end].acc_routing_costs
    inventory_cost = isempty(new_solution.calls) ? 0.0 : new_solution.calls[end].acc_inventory_costs
    inventory, penalty = advance_inventory(
        mirp,
        port,
        new_solution.port_inventory[port_id],
        new_solution.port_time[port_id],
        service_time - 1,
    )
    new_solution.port_inventory[port_id] = inventory
    inventory_cost += penalty

    cargo_before = new_solution.vessel_inventory[vessel_id]
    routing_cost += route_cost(mirp, vessel, from_port, port, cargo_before)
    inventory_cost += apply_service!(mirp, new_solution, call, service_time)

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
    call.inventory_level = new_solution.port_inventory[port_id]
    call.next_violation_time = next_violation_period(port, call.inventory_level, service_time, time_horizon)
    new_solution.port_next_violation[port_id] = call.next_violation_time
    call.acc_routing_costs = routing_cost
    call.acc_inventory_costs = inventory_cost
    call.acc_total_costs = routing_cost + inventory_cost

    push!(new_solution.calls, call)
    new_solution.last_occ_ports[port_id] = call
    new_solution.last_occ_vessels[vessel_id] = call
    new_solution.port_time[port_id] = service_time
    new_solution.vessel_time[vessel_id] = service_time
    new_solution.score = routing_cost + inventory_cost
    new_solution.feasible = true
    return new_solution
end

# Main schedule evaluator used by construction, neighborhoods, and final scoring.
function evaluate_solution!(mirp::MIRP, solution::Solution; add_final_inventory_cost::Bool = true)
    reset_solution_state!(solution, mirp)

    time_horizon = horizon(mirp)
    berth_use = [Dict{Int64, Int64}() for _ in mirp.ports]
    routing_cost = 0.0
    inventory_cost = 0.0

    for call in solution.calls
        if !is_feasible(solution, call.port, call.vessel)
            # This branch is pruned; callers keep the parent prefix and try another extension.
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
            # No schedulable period exists for this appended call, so this branch is discarded.
            solution.feasible = false
            solution.score = Inf
            return solution
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
    end

    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end

function weighted_choice(items::Vector, weights::Vector{Float64}, rng::AbstractRNG)
    total_weight = sum(weights)
    if total_weight <= 0.0
        return items[1]
    end

    threshold = rand(rng) * total_weight
    cumulative = 0.0
    for (item, weight) in zip(items, weights)
        cumulative += weight
        if cumulative >= threshold
            return item
        end
    end

    return items[end]
end

function early_time_weights(times::Vector{Int64})
    earliest = minimum(times)
    spread = max(1.0, (maximum(times) - earliest) / 2.0)
    return [exp(-0.5 * ((time - earliest) / spread)^2) for time in times]
end

# Greedy randomized completion: repeatedly repair the most urgent inventory risk
# with a feasible vessel, skipping unschedulable extensions for this prefix.
function greedy_complete_solution(
    mirp::MIRP,
    partial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    randomize_port::Bool = false,
    randomize_vessel::Bool = false,
)
    # Beam nodes normally arrive with evaluated prefix state. Neighborhood output
    # may not, so rebuild once only when the cached service fields are missing. 
    # TODO: Neighbouthood output woulld not call greedy_complete_solution at all as its only used in beam_search
    solution = if partial_solution.feasible && all(call -> call.service_time_port > 0, partial_solution.calls)
        clone_evaluated_solution(mirp, partial_solution)
    else
        evaluate_solution!(mirp, clone_solution(mirp, partial_solution); add_final_inventory_cost = false)
    end

    if !solution.feasible
        return solution
    end

    # A skipped port failed for the current prefix. After any successful append,
    # the prefix changes, so those ports are allowed to compete again.
    skipped_port_ids = Set{Int64}()
    while true
        time_horizon = horizon(mirp)
        port_candidates = Tuple{Port, Int64}[]

        # Read cached violation periods instead of simulating each port again.
        for port in mirp.ports
            port.id in skipped_port_ids && continue
            any(vessel -> is_feasible(solution, port, vessel), mirp.vessels) || continue

            violation_time = solution.port_next_violation[port.id]
            violation_time <= time_horizon && push!(port_candidates, (port, violation_time))
        end

        sort!(port_candidates, by = candidate -> candidate[2])
        if isempty(port_candidates)
            break
        end

        # Select the next at-risk port, deterministically or weighted toward earlier violations.
        port = if randomize_port
            ports = [candidate[1] for candidate in port_candidates]
            times = [candidate[2] for candidate in port_candidates]
            weighted_choice(ports, early_time_weights(times), rng)
        else
            port_candidates[1][1]
        end

        vessel_options = Tuple{Vessel, Int64, Solution}[]
        for vessel in mirp.vessels
            is_feasible(solution, port, vessel) || continue

            # Trial append evaluates only this vessel-port call; the current
            # prefix is kept if the trial cannot be scheduled.
            candidate = append_evaluated_call(mirp, solution, port, vessel)
            candidate.feasible || continue

            push!(vessel_options, (vessel, candidate.calls[end].service_time_port, candidate))
        end

        # No vessel can serve this port from the current prefix, so avoid
        # repeatedly choosing the same urgent-but-unschedulable port.
        if isempty(vessel_options)
            push!(skipped_port_ids, port.id)
            continue
        end

        sort!(vessel_options, by = option -> option[2])

        # The deterministic GRA uses earliest service. Stochastic vessel choice
        # samples from feasible services with higher weight for earlier service.
        candidate = if randomize_vessel
            vessels = [option[1] for option in vessel_options]
            service_times = [option[2] for option in vessel_options]
            vessel = weighted_choice(vessels, early_time_weights(service_times), rng)
            vessel_options[findfirst(option -> option[1].id == vessel.id, vessel_options)][3]
        else
            vessel_options[1][3]
        end

        solution = candidate
        empty!(skipped_port_ids)
    end

    if !solution.feasible
        return solution
    end

    routing_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_routing_costs
    inventory_cost = isempty(solution.calls) ? 0.0 : solution.calls[end].acc_inventory_costs
    time_horizon = horizon(mirp)

    # Greedy completion was evaluated as a prefix. Charge the remaining inventory
    # penalties through the horizon only once, after no more calls can be added.
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

    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end

function deterministic_eval(node::Solution, mirp::MIRP)
    return greedy_complete_solution(mirp, node; randomize_port = false, randomize_vessel = false)
end

function stochastic_eval(
    node::Solution,
    mirp::MIRP;
    rng::AbstractRNG = Random.default_rng(),
    randomize_port::Bool = true,
    randomize_vessel::Bool = false,
)
    return greedy_complete_solution(
        mirp,
        node;
        rng = rng,
        randomize_port = randomize_port,
        randomize_vessel = randomize_vessel,
    )
end
