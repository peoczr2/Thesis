using MIRPLib
using Random

const DEFAULT_INSTANCE = :LR1_1_DR1_3_VC1_V7a
const DEFAULT_HORIZON = 60
const INSTANCE = loadMIRP(DEFAULT_INSTANCE, DEFAULT_HORIZON)

if INSTANCE === nothing
    error("Could not load MIRP instance $(DEFAULT_INSTANCE).")
end

include("solution_var.jl")
include("greedy_randomize_algorithm.jl")
include("beam_search.jl")
include("neighbourhood.jl")
include("local_search.jl")
include("iterated_local_search.jl")

# Small smoke entry point for running beam search on the default MIRPLib case.
function main(; N::Int64 = 100, w::Int64 = 2, q::Int64 = 3, seed::Int64 = 1)
    rng = MersenneTwister(seed)
    result = beam_search(INSTANCE; N = N, w = w, q = q, rng = rng)

    println("Beam Search completed after $(result.levels) levels.")
    println("Best cost: $(result.best_solution.score)")
    println("Number of calls: $(length(result.best_solution.calls))")

    return result
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
