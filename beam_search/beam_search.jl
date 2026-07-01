using Random
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

"""
Selects the best N solution all with different scores.
The paper keeps unique nodes by score, rounding helps with precision.
"""
function keep_best_N_unique(nodes::Vector{Solution}, N::Int64)
    selected = sizehint!(Solution[], N)
    seen_scores = sizehint!(Set{Float64}(), N)

    sorted_nodes = filter(node -> node.feasible && isfinite(node.score), nodes)
    sort!(sorted_nodes, by = node -> node.score)

    for node in sorted_nodes
        key = score_key(node)
        if !(key in seen_scores)
            push!(seen_scores, key)
            push!(selected, node)
            
            length(selected) == N && break
        end
    end

    return selected
end

"""
Modifies pool in place to efficiently keep the best N unique solutions from the 
previously saved N solutions and the new candidates using a pre-allocated scratch vector.
Both best_n and candidates must be SORTED ascending by score.
"""
function keep_best_N_solutions!(
    best_n::Vector{Solution},
    sorted_candidates::Vector{Solution},
    helper::Vector{Solution},
    N::Int
)
    i = 1
    j = 1
    k = 1

    len_b = length(best_n)
    len_c = length(sorted_candidates)

    last_key = nothing
    have_last_key = false

    while k <= N && (i <= len_b || j <= len_c)
        if i <= len_b && (j > len_c || best_n[i].score <= sorted_candidates[j].score)
            candidate = best_n[i]
            i += 1
        else
            candidate = sorted_candidates[j]
            j += 1
        end

        !candidate.feasible || !isfinite(candidate.score) && continue

        key = score_key(candidate)

        have_last_key && key == last_key && continue

        helper[k] = candidate
        last_key = key
        have_last_key = true
        k += 1
    end

    actual_size = k - 1
    resize!(best_n, actual_size)

    for idx in 1:actual_size
        best_n[idx] = helper[idx]
    end

    return best_n
end

function validate_beam_search_args(N::Int64, w::Int64, q::Int64, model::AbstractNodeScorer)
    if N < 1 || w < 1 || q < 1
        throw(ArgumentError("N, w, and q must be positive integers."))
    end
    return model # TODO: maybe validate model type and parameters
end

function possible_calls(mirp::MIRP, node::Solution)
    calls = Call[]
    sizehint!(calls, length(mirp.ports) * length(mirp.vessels))

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

"""
Expand one beam node, score each feasible successor.
Return: (SORTED best w children, SORTED completed solutions)
"""
function expand_node(
    mirp::MIRP,
    node::Solution,
    w::Int64,
    level::Int64,
    model::AbstractNodeScorer;
    rng::AbstractRNG = Random.default_rng(),
)
    calls = possible_calls(mirp, node)
    successors = Solution[]
    sizehint!(successors, length(calls))

    for call in calls
        successor = create_new_node(mirp, node, call)
        successor.feasible && push!(successors, successor)
    end

    return score_successors!(model, mirp, successors, w, level; rng = rng)
end

# Main beam loop: expand a frontier, globally retain the best N successors, and
# keep completed greedy solutions as incumbent candidates.
function beam_search(
    mirp::MIRP;
    N::Int64 = 100,
    w::Int64 = 2,
    q::Int64 = 3,
    rng::AbstractRNG = Random.default_rng(),
    model::AbstractNodeScorer = GRABeamScorer(q),
)
    validate_beam_search_args(N, w, q, model)

    initial_node = evaluate_solution!(mirp, Solution(mirp); add_final_inventory_cost = false) # TODO: maybe create an initial node with the initial things from the mirp data, like for vessels intial port etc
    beam_nodes = [initial_node]
    best_n = sizehint!(Solution[], N)
    best_n_helper = Vector{Solution}(undef, N)
    levels = 0

    while !isempty(beam_nodes)
        successors = Solution[] # maybe sizehint this or take it outside the while or like use reset idk

        for node in beam_nodes
            node_successors, completed_solutions = expand_node(mirp, node, w, levels, model; rng = rng)
            append!(successors, node_successors)
            sort!(completed_solutions, by = solution -> solution.score)
            keep_best_N_solutions!(best_n, completed_solutions, best_n_helper, N)
        end

        if isempty(successors)
            break
        end

        beam_nodes = keep_best_N_unique(successors, N) # TODO: this could be more efficient with better datastructure
        levels += 1
    end
    
    fallback = evaluate_solution!(mirp, Solution(mirp); add_final_inventory_cost = true) # TODO: ... not sure if this is needed, as the initial node should be already included
    ranked_final_candidates = keep_best_N_unique(vcat(best_n, [fallback]), N)
    best_solution = ranked_final_candidates[1]

    return BeamSearchResult(best_solution, ranked_final_candidates, beam_nodes, levels)
end


"""
function beam_search(N::Int64, w::Int64, q::Int64)
    if !isdefined(Main, :INSTANCE)
        throw(ArgumentError("Call beam_search(mirp; N = N, w = w, q = q) or define a global INSTANCE."))
    end

    return beam_search(Main.INSTANCE; N = N, w = w, q = q)
end
"""