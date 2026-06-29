using MIRPLib
using Random

const DEFAULT_INSTANCE = :LR1_1_DR1_3_VC1_V7a
const DEFAULT_HORIZON = 60
const INSTANCE = loadMIRP(DEFAULT_INSTANCE, DEFAULT_HORIZON)

if INSTANCE === nothing
    error("Could not load MIRP instance $(DEFAULT_INSTANCE).")
end

include("solution_var.jl")
include("evaluate.jl")
include("evaluate_neighbor.jl")
include("greedy_randomize_algorithm.jl")
include("beam_search/predictive_beam_model.jl")
include("beam_search/beam_scorers.jl")
include("beam_search/beam_search.jl")
include("neighbourhood.jl")
include("local_search.jl")
include("iterated_local_search.jl")

# Small smoke entry point for running beam search on the default MIRPLib case.
function main(;
    N::Int64 = 100,
    w::Int64 = 2,
    q::Int64 = 3,
    seed::Int64 = 1,
    scorer::Symbol = DEFAULT_BEAM_SCORER,
    surrogate_shortlist_multiplier::Int64 = 2,
    surrogate_warmup_levels::Int64 = 1,
    surrogate_model::Symbol = :linear,
    surrogate_forest_trees::Int64 = 8,
)
    rng = MersenneTwister(seed)
    beam_model = create_beam_scorer(
        scorer;
        q = q,
        surrogate_model = surrogate_model,
        surrogate_shortlist_multiplier = surrogate_shortlist_multiplier,
        surrogate_warmup_levels = surrogate_warmup_levels,
        surrogate_forest_trees = surrogate_forest_trees,
        rng = rng,
    )
    result = beam_search(
        INSTANCE;
        N = N,
        w = w,
        rng = rng,
        model = beam_model,
    )

    println("Beam Search ($(scorer), surrogate=$(surrogate_model)) completed after $(result.levels) levels.")
    println("Best cost: $(result.best_solution.score)")
    println("Number of calls: $(length(result.best_solution.calls))")

    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
