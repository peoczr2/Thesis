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
    # TODO: clarify this: How is it possible that a port can not be served by any vessel, but later could be? Its possible that a port can not be served by any vessel until time_horizon, but in this case later should not be considered too. Or maybe like no vessel has capaciy so they first have to go to a loading port for example. Anyway this has to be clarified
    skipped_port_ids = Set{Int64}()
    while true
        time_horizon = horizon(mirp) # TODO: time_horizon is constant given an MIRP instance, so it could be outside of the while loop
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

        vessel_options = Tuple{Vessel, Int64, Solution}[] # TODO: this should not store Solutions at all only the feasible or like good options of vessels, as making and hardcopying multiple solutions in each iteration is very inefficient
        for vessel in mirp.vessels
            is_feasible(solution, port, vessel) || continue

            # Trial append evaluates only this vessel-port call; the current
            # prefix is kept if the trial cannot be scheduled.
            # TODO: this is not efficient, though in theory its O(1) as it only evaluates the last call, so maybe it is fine, but make sure that append_evaluated_call should not copy prefix solutions and rather just either return the service time and feasibility or a bigger evaluation object 
            candidate = append_evaluated_call(mirp, solution, port, vessel) # TODO: make sure this does not hard copy but rather just appends, though then it has to be handled carefully that the newly added call might results in an infeasible solution or like an infeasible call as its service after the horizon then maybe just the previous result should be retruned, and handled some how with the skipped_ports or vessels, or actually this is just for seeing if the vessel is a good option: so it actually services before the horizon
            # TODO: actually maybe another function should be called instead of append_evaluated_call that just checks if the vessel can serve the port before the horizon
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

        # TODO: here somewhere a finaly append_evaluated_call should be called as vessel_option should only store the vessel id or the vessel but not a whole complete seperate solution
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
