const MIRP = loadMIRP(:LR1_1_DR1_3_VC1_V7a, 60)

include("solution_var.jl")
include("greedy_randomize_algorithm.jl")
include("beam_search.jl")

function main()
    beam_search(N, w, q)
end