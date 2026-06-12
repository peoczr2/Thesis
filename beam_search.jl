using Random
using Statistics
using MIRPLib

const SCORE_KEY_DIGITS = 6

struct BeamSearchResult
    best_solution::Solution
    best_solutions::Vector{Solution}
    final_beam::Vector{Solution}
    levels::Int64
end

function score_key(solution::Solution)
    return round(solution.score; digits = SCORE_KEY_DIGITS)
end

# The paper keeps unique nodes by score; rounding avoids floating point noise
# producing duplicate beam entries.
function keep_best_N_unique(nodes::Vector{Solution}, N::Int64)
    sorted_nodes = sort(
        [node for node in nodes if node.feasible && isfinite(node.score)],
        by = node -> node.score,
    )
    selected = Solution[]
    seen_scores = Set{Float64}()

    for node in sorted_nodes
        key = score_key(node)
        if key in seen_scores
            continue
        end

        push!(selected, node)
        push!(seen_scores, key)

        if length(selected) == N
            break
        end
    end

    return selected
end

function keep_best_unique(nodes::Vector{Solution}, N::Int64)
    return keep_best_N_unique(nodes, N)
end

function keep_best_N_nodes(nodes::Vector{Solution}, N::Int64)
    return keep_best_N_unique(nodes, N)
end

function keep_best_N_solutions!(pool::Vector{Solution}, candidates::Vector{Solution}, N::Int64)
    append!(pool, candidates)
    best = keep_best_N_unique(pool, N)
    empty!(pool)
    append!(pool, best)
    return pool
end

# Evaluate a partial node with one deterministic and q - 1 randomized completions.
# The node receives the median completion score as its beam priority.
function evaluate(node::Solution, mirp::MIRP, q::Int64; rng::AbstractRNG = Random.default_rng())
    full_solutions = Solution[]

    push!(full_solutions, deterministic_eval(node, mirp))
    for _ in 2:q
        push!(full_solutions, stochastic_eval(node, mirp; rng = rng, randomize_port = true, randomize_vessel = false))
    end

    scores = [solution.score for solution in full_solutions if solution.feasible && isfinite(solution.score)]
    node.score = isempty(scores) ? Inf : median(scores)
    return full_solutions
end

function possible_calls(mirp::MIRP, node::Solution)
    calls = Call[]

    for port in mirp.ports
        for vessel in mirp.vessels
            if is_feasible(node, port, vessel)
                push!(calls, Call(port, vessel))
            end
        end
    end

    return calls
end

function create_new_node(mirp::MIRP, node::Solution, call::Call)
    return append_evaluated_call(mirp, node, call.port, call.vessel)
end

# Expand one beam node, score each feasible successor, and keep its best w children.
function expand_node(
    mirp::MIRP,
    node::Solution,
    w::Int64,
    q::Int64;
    rng::AbstractRNG = Random.default_rng(),
)
    successors = Solution[]
    completed_solutions = Solution[]

    for call in possible_calls(mirp, node)
        successor = create_new_node(mirp, node, call)
        if !successor.feasible
            continue
        end

        all_eval_sol = evaluate(successor, mirp, q; rng = rng)
        append!(completed_solutions, all_eval_sol)
        push!(successors, successor)
    end

    return keep_best_unique(successors, w), completed_solutions
end

# Main beam loop: expand a frontier, globally retain the best N successors, and
# keep completed greedy solutions as incumbent candidates.
function beam_search(
    mirp::MIRP;
    N::Int64 = 100,
    w::Int64 = 2,
    q::Int64 = 3,
    rng::AbstractRNG = Random.default_rng(),
)
    if N < 1 || w < 1 || q < 1
        throw(ArgumentError("N, w, and q must be positive integers."))
    end

    initial_node = evaluate_solution!(mirp, Solution(mirp); add_final_inventory_cost = false)
    beam_nodes = [initial_node]
    best_solutions = Solution[]
    levels = 0

    while !isempty(beam_nodes)
        successors = Solution[]

        for node in beam_nodes
            node_successors, completed_solutions = expand_node(mirp, node, w, q; rng = rng)
            append!(successors, node_successors)
            keep_best_N_solutions!(best_solutions, completed_solutions, N)
        end

        if isempty(successors)
            break
        end

        beam_nodes = keep_best_N_nodes(successors, N)
        levels += 1
    end

    fallback = evaluate_solution!(mirp, Solution(mirp); add_final_inventory_cost = true)
    ranked_final_candidates = keep_best_unique(vcat(best_solutions, [fallback]), max(1, N))
    best_solution = ranked_final_candidates[1]

    return BeamSearchResult(best_solution, ranked_final_candidates, beam_nodes, levels)
end

function beam_search(N::Int64, w::Int64, q::Int64)
    if !isdefined(Main, :INSTANCE)
        throw(ArgumentError("Call beam_search(mirp; N = N, w = w, q = q) or define a global INSTANCE."))
    end

    return beam_search(Main.INSTANCE; N = N, w = w, q = q)
end
