
using Random

# Table 4 parameters from the paper's ILS tuning section.
Base.@kwdef struct ILSParameters
    initial_probability::Float64 = 0.79
    final_probability::Float64 = 0.01
    iterations::Int64 = 640
    restore_after::Int64 = 4
    perturbations::Int64 = 2
end

const PAPER_ILS_PARAMETERS = ILSParameters()

# Exponential interpolation between the reported initial and final acceptance
# probabilities for non-improving moves.
function annealing_probability(iteration::Int64, params::ILSParameters)
    if params.iterations <= 1
        return params.final_probability
    end

    progress = (iteration - 1) / (params.iterations - 1)
    return params.initial_probability * (params.final_probability / params.initial_probability)^progress
end

function sim_annealing_criterion(
    new_solution::Solution,
    current_solution::Solution,
    iteration::Int64,
    params::ILSParameters,
    rng::AbstractRNG,
)
    new_solution.score + EPS < current_solution.score && return true
    return rand(rng) <= annealing_probability(iteration, params)
end

# Perturb, locally improve, accept with simulated annealing, and periodically
# restore the search to the best incumbent after accepted non-improvements.
function iterated_local_search(
    mirp::MIRP,
    initial_solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    params::ILSParameters = PAPER_ILS_PARAMETERS,
    randomize::Bool = true,
)
    current_solution = local_search(mirp, initial_solution; rng = rng, randomize = randomize) # TODO: is this even neccessary? I mean conceptually as well the initila soultion does not have to be the best
    best_solution = clone_solution(mirp, current_solution)
    evaluate_solution!(mirp, best_solution; add_final_inventory_cost = true)
    no_improvement = 0

    for iteration in 1:params.iterations
        new_solution = current_solution # TODO: this might be wrong as it needs to be hard copy
        for _ in 1:params.perturbations
            new_solution = apply_perturbation(mirp, new_solution; rng = rng, randomize = randomize) # TODO: maybe hard copy the current_solution to new_solution beforehand and have apply_perturbation just modify the new_solution
        end

        new_solution = local_search(mirp, new_solution; rng = rng, randomize = randomize)

        if sim_annealing_criterion(new_solution, current_solution, iteration, params, rng)
            if new_solution.score + EPS < best_solution.score
                # TODO: is this even neccessary?
                best_solution = clone_solution(mirp, new_solution)
                evaluate_solution!(mirp, best_solution; add_final_inventory_cost = true)
                no_improvement = 0
            else
                no_improvement += 1
            end

            current_solution = new_solution
        end

        if no_improvement >= params.restore_after
            # TODO: is this even neccessary?
            current_solution = clone_solution(mirp, best_solution)
            evaluate_solution!(mirp, current_solution; add_final_inventory_cost = true) # TODO: i mean it should have already been evluated at this point
            no_improvement = 0
        end
    end

    return best_solution
end
