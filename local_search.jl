
using Random

"""
Randomized Variable Neighborhood Descent (RVND), using first improvement.
Modifies the initial solution
Neighborhoods first efficiently scores neighbors with a reusable call evaluator, 
if the score is better than the current solution is modified by applying the neighbor change.
After no better solution can be found the solution is returned.
"""
function local_search!(
    mirp::MIRP,
    initial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    neighborhoods_to_use::Vector{Symbol} = collect(NEIGHBORHOODS),
    randomize::Bool = true,
)
    current_solution = initial_solution
    !current_solution.feasible && return current_solution # TODO: what is even this line for? I mean local_search would obviously get a feasible solution(every solution is feasible only calls are not), then local_search trys to find a better solution

    evaluator = CallEvaluator(mirp)
    found_better_solution = true
    while found_better_solution
        found_better_solution = false

        neighborhood_order = randomize ? shuffle(rng, copy(neighborhoods_to_use)) : copy(neighborhoods_to_use)
        for neighborhood in neighborhood_order
            neighbor = neighborhood_neighbor!(
                mirp,
                current_solution,
                neighborhood,
                current_solution.score;
                rng = rng,
                randomize = randomize,
                evaluator = evaluator,
            )
            neighbor === nothing && continue

            current_solution = neighbor # apply_neighbor_move(mirp, current_solution, neighbor)
            found_better_solution = true
            break
        end
    end

    return current_solution
end

"""
Hard copys the initial solution and then retruns the local_search! result on that hard copy. If no better solution is found, nothing is returned
"""
function local_search(
    mirp::MIRP,
    initial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    neighborhoods_to_use::Vector{Symbol} = collect(NEIGHBORHOODS),
    randomize::Bool = true,
)
    current_solution = evaluate_solution!(mirp, clone_solution(mirp, initial_solution); add_final_inventory_cost = true) # TODO: needs to be hard copy
    !current_solution.feasible && return current_solution # TODO: what is even this line for? I mean local_search would obviously get a feasible solution(every solution is feasible only calls are not), then local_search trys to find a better solution

    return local_search!(mirp, current_solution; rng = rng, neighborhoods_to_use = neighborhoods_to_use, randomize = randomize)
end
