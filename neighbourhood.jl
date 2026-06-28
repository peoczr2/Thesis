
using Random

# Neighborhoods used by RVND and by the ILS perturbation step.
const NEIGHBORHOODS = [:swap, :relocate, :replace, :insert, :remove, :swap_port]
const neigbourhoods = NEIGHBORHOODS
const neighborhoods = NEIGHBORHOODS

function ordered_indices(rng::AbstractRNG, n::Int64, randomize::Bool)
    return randomize ? randperm(rng, n) : Base.OneTo(n)
end

function ordered_items(rng::AbstractRNG, items, randomize::Bool)
    return randomize ? shuffle(rng, collect(items)) : items
end

function accepted_score(score::Float64, current_score::Union{Nothing, Float64})
    isfinite(score) || return false
    current_score === nothing && return true
    return score + EPS < current_score
end

"""
modifys the solution and returns it
"""
function apply_swap!(mirp::MIRP, solution::Solution, i::Int64, j::Int64, score::Float64)
    solution.calls[i], solution.calls[j] = solution.calls[j], solution.calls[i]
    return evaluate_suffix_neighbor!(mirp, solution, i-1) # the point is that it only needs to evaluate from i(including), with solution modified
end

"""
finds an improving neighbor and modifies the pass solution and returns it, or returns nothing if no improving neighbor was found
"""
function swap_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    n = length(solution.calls)

    for i in ordered_indices(rng, max(n - 1, 0), randomize)
        for j in ordered_indices(rng, n, randomize)
            i < j || continue

            score = score_swap!(evaluator, mirp, solution, i, j)
            accepted_score(score, current_score) && return apply_swap!(mirp, solution, i, j, score)
        end
    end

    return nothing
end


function apply_relocate!(mirp::MIRP, solution::Solution, i::Int64, j::Int64, score::Float64)
    call = solution.calls[i]
    popat!(solution.calls, i)
    insert!(solution.calls, j, call)
    return evaluate_suffix_neighbor!(mirp, solution, min(i, j) - 1)
end
function relocate_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    n = length(solution.calls)

    for i in ordered_indices(rng, n, randomize)
        for j in ordered_indices(rng, n, randomize)
            i == j && continue

            score = score_relocate!(evaluator, mirp, solution, i, j)
            accepted_score(score, current_score) && return apply_relocate!(mirp, solution, i, j, score)
        end
    end

    return nothing
end


function apply_replace!(mirp::MIRP, solution::Solution, i::Int64, port::Port, score::Float64)
    solution.calls[i] = Call(port, solution.calls[i].vessel)
    return evaluate_suffix_neighbor!(mirp, solution, i-1)
end
function replace_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    for i in ordered_indices(rng, length(solution.calls), randomize)
        call = solution.calls[i]

        for port in ordered_items(rng, mirp.ports, randomize)
            if port.id == call.port.id || port.type != call.port.type
                continue
            end

            score = score_replace!(evaluator, mirp, solution, i, port)
            accepted_score(score, current_score) && return apply_replace!(mirp, solution, i, port, score)
        end
    end

    return nothing
end
function apply_insert!(mirp::MIRP, solution::Solution, i::Int64, j::Int64, score::Float64; port::Port, second_port::Port, vessel::Vessel)
    insert!(solution.calls, i, Call(port, vessel))
    insert!(solution.calls, j, Call(second_port, vessel))
    return evaluate_suffix_neighbor!(mirp, solution, min(i, j) - 1)
    
end
"""
Insert a short feasible loading/unloading cycle for one vessel.
"""
function insert_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    for first_port in ordered_items(rng, mirp.ports, randomize)
        for vessel in ordered_items(rng, mirp.vessels, randomize)
            for port in ordered_items(rng, mirp.ports, randomize)
                port.type == first_port.type && continue

                score = score_insert!(evaluator, mirp, solution, first_port, vessel, port)
                accepted_score(score, current_score) && return apply_insert!(mirp, solution, length(solution.calls) + 1, length(solution.calls) + 2, score; port = first_port, second_port = port, vessel = vessel)
            end
        end
    end

    return nothing
end

function next_same_vessel_index(calls::Vector{Call}, start_index::Int64)
    vessel_id = calls[start_index].vessel.id
    for j in (start_index + 1):length(calls)
        if calls[j].vessel.id == vessel_id
            return j
        end
    end
    return nothing
end


function apply_remove!(mirp::MIRP, solution::Solution, i::Int64, j::Union{Nothing, Int64}, score::Float64)
    if j === nothing
        popat!(solution.calls, i)
        return evaluate_suffix_neighbor!(mirp, solution, i - 1)
    end

    popat!(solution.calls, max(i, j))
    popat!(solution.calls, min(i, j))
    return evaluate_suffix_neighbor!(mirp, solution, min(i, j) - 1)
end
"""
Remove a call and, when present, the next call of the same vessel to preserve
the load/unload alternation more often than a single deletion would.
"""
function remove_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    n = length(solution.calls)

    for i in ordered_indices(rng, n, randomize)
        j = next_same_vessel_index(solution.calls, i)
        score = score_remove!(evaluator, mirp, solution, i, j)
        accepted_score(score, current_score) && return apply_remove!(mirp, solution, i, j, score)
    end

    return nothing
end


function apply_swap_port!(mirp::MIRP, solution::Solution, i::Int64, j::Int64, score::Float64)
    call_i = solution.calls[i]
    call_j = solution.calls[j]
    solution.calls[i] = Call(call_j.port, call_i.vessel)
    solution.calls[j] = Call(call_i.port, call_j.vessel)
    return evaluate_suffix_neighbor!(mirp, solution, min(i, j) - 1)
end
"""
Swap compatible ports between two calls while keeping the assigned vessels.
"""
function swap_port_neighbor!(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    n = length(solution.calls)

    for i in ordered_indices(rng, max(n - 1, 0), randomize)
        for j in ordered_indices(rng, n, randomize)
            i < j || continue

            call_i = solution.calls[i]
            call_j = solution.calls[j]
            if call_i.port.type != call_j.port.type || call_i.port.id == call_j.port.id
                continue
            end

            score = score_swap_port!(evaluator, mirp, solution, i, j)
            accepted_score(score, current_score) && return apply_swap_port!(mirp, solution, i, j, score)
        end
    end

    return nothing
end

"""
Modifies the original solution and returns it or nothing if no better solution was found
"""
function neighborhood_neighbor!(
    mirp::MIRP,
    solution::Solution,
    neighborhood::Symbol,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    source_solution = neighbor_source_solution(mirp, solution)

    if neighborhood == :swap
        return swap_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    elseif neighborhood == :relocate
        return relocate_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    elseif neighborhood == :replace
        return replace_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    elseif neighborhood == :insert
        return insert_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    elseif neighborhood == :remove
        return remove_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    elseif neighborhood == :swap_port
        return swap_port_neighbor!(mirp, source_solution, current_score; rng = rng, randomize = randomize, evaluator = evaluator)
    end

    throw(ArgumentError("Unknown neighborhood: $(neighborhood)"))
end

"""function apply_neighborhood!( not needed for now
    mirp::MIRP,
    solution::Solution,
    neighborhood::Symbol;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    source_solution = neighbor_source_solution(mirp, solution)
    move = neighborhood_neighbor!(
        mirp,
        source_solution,
        neighborhood;
        rng = rng,
        randomize = randomize,
        evaluator = evaluator,
    )
    return move === nothing ? clone_solution(mirp, source_solution) : apply_neighbor_move(mirp, source_solution, move)
end"""

"""
Modifies the solution by applying a perturbation to it by exploring its neighborhood and returns that modified solution.
"""
function apply_perturbation!(
    mirp::MIRP,
    solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    source_solution = neighbor_source_solution(mirp, solution)
    neighborhood_order = randomize ? shuffle(rng, collect(NEIGHBORHOODS)) : collect(NEIGHBORHOODS)
    for neighborhood in neighborhood_order
        move = neighborhood_neighbor!(
            mirp,
            source_solution,
            neighborhood;
            rng = rng,
            randomize = randomize,
            evaluator = evaluator,
        )
        move !== nothing && return move
    end

    return source_solution
end
