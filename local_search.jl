
using Random

# Randomized Variable Neighborhood Descent (RVND), using first improvement.
# After an improvement the neighborhood order is reshuffled from the start.
function local_search(
    mirp::MIRP,
    initial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    neighborhoods_to_use::Vector{Symbol} = collect(NEIGHBORHOODS),
)
    current_solution = evaluate_solution!(mirp, clone_solution(mirp, initial_solution); add_final_inventory_cost = true)
    !current_solution.feasible && return current_solution # TODO: what is even this line for? I mean local_search would obviously get a feasible solution(every solution is feasible only calls are not), then local_search trys to find a better solution

    found_better_solution = true
    while found_better_solution
        found_better_solution = false

        for neighborhood in shuffle(rng, copy(neighborhoods_to_use))
            # TODO: this is just hugely inefficient, i mean precalculating every possible candidates for a given neighborhood, then shuffling them and only choosing the first one
            candidates = neighborhood_candidates(mirp, current_solution, neighborhood)
            isempty(candidates) && continue

            for candidate in shuffle(rng, candidates)
                if candidate.score + EPS < current_solution.score
                    current_solution = candidate
                    found_better_solution = true
                    break
                end
            end

            found_better_solution && break
        end
    end

    return current_solution
end
