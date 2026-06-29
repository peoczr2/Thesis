using Random
using Statistics
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

"""
partial_solution: already evaluated solution
Greedy randomized completion: repeatedly repair the most urgent inventory risk with a feasible vessel, skipping unschedulable extensions for this prefix.
Does not modify partial_solution, but returns a new evaluated solution with a final score.
"""
function greedy_complete_solution(
    mirp::MIRP,
    partial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    randomize_port::Bool = false,
    randomize_vessel::Bool = false,
)
    solution = clone_evaluated_solution(mirp, partial_solution)

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

    finalize_evaluation!(mirp, solution)
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

"""
Evaluate a partial node with one deterministic and q - 1 randomized completions.
The node receives the median completion score as its score.
Returns the GRA created full_solutions
"""
function evaluate(node::Solution, mirp::MIRP, q::Int64; rng::AbstractRNG = Random.default_rng())
    full_solutions = sizehint!(Solution[], q)
    scores = sizehint!(Float64[], q)

    deterministic_solution = deterministic_eval(node, mirp)
    push!(full_solutions, deterministic_solution)
    deterministic_solution.feasible && isfinite(deterministic_solution.score) && push!(scores, deterministic_solution.score) # TODO: why would a returned solution not be feasible...

    for _ in 2:q
        solution = stochastic_eval(node, mirp; rng = rng, randomize_port = true, randomize_vessel = false)
        push!(full_solutions, solution)
        solution.feasible && isfinite(solution.score) && push!(scores, solution.score)
    end

    node.score = isempty(scores) ? Inf : median!(scores)
    return full_solutions
end
