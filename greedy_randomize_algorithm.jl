using Random
using MIRPLib

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
    # TODO: Neighbouthood output woulld not call greedy_complete_solution at all as its only used in beam_search, could be deleted, but lets have an easy mechanism to check if a solution has been evaluated fully
    solution = if partial_solution.feasible &&
        !isempty(partial_solution.calls) &&
        all(call -> call.service_time_port > 0, partial_solution.calls)
        clone_evaluated_solution(mirp, partial_solution)
    else
        evaluate_solution!(mirp, clone_solution(mirp, partial_solution); add_final_inventory_cost = false)
    end

    if !solution.feasible
        return solution
    end

    # A skipped port failed for the current prefix. After any successful append,
    # the prefix changes, so those ports are allowed to compete again.
    # TODO: clarify this: How is it possible that a port can not be served by any vessel, but later could be? Its possible that a port can not be served by any vessel until time_horizon, but in this case later should not be considered too. Or maybe like no vessel has capaciy so they first have to go to a loading port for example. Anyway this has to be clarified
    skipped_port_ids = Set{Int64}()
    time_horizon = horizon(mirp)
    while true
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

        vessel_options = AppendCandidate[]
        berth_use = berth_use_for_port(solution, port.id)
        for vessel in mirp.vessels
            candidate = candidate_append(mirp, solution, port, vessel, berth_use)
            candidate === nothing && continue

            push!(vessel_options, candidate)
        end

        # No vessel can serve this port from the current prefix, so avoid
        # repeatedly choosing the same urgent-but-unschedulable port.
        if isempty(vessel_options)
            push!(skipped_port_ids, port.id)
            continue
        end

        sort!(vessel_options, by = candidate -> (candidate.arrival_time, candidate.service_time, candidate.vessel.id))

        # The deterministic GRA uses earliest arrival. Stochastic vessel choice
        # samples from feasible arrivals with higher weight for earlier arrival.
        candidate = if randomize_vessel
            arrival_times = [option.arrival_time for option in vessel_options]
            weighted_choice(vessel_options, early_time_weights(arrival_times), rng)
        else
            vessel_options[1]
        end

        append_evaluated_call!(mirp, solution, candidate)
        empty!(skipped_port_ids)
    end

    # TODO: why would not a solution be feasible at this point, like its a greedy completion. If there are ports that can not be served by any vessel before the horizon are a violated their inventory, then just add the penalty costs
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

    routing_cost -= early_finish_reward(mirp, solution)

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
