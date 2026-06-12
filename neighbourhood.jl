
using Random

# Neighborhoods used by RVND and by the ILS perturbation step.
const NEIGHBORHOODS = [:swap, :relocate, :replace, :insert, :remove, :swap_port]
const neigbourhoods = NEIGHBORHOODS
const neighborhoods = NEIGHBORHOODS

function evaluated_neighbor(mirp::MIRP, calls::Vector{Call})
    return evaluate_solution!(mirp, Solution(mirp, calls); add_final_inventory_cost = true)
end

function feasible_neighbor(mirp::MIRP, calls::Vector{Call})
    solution = evaluated_neighbor(mirp, calls)
    return solution.feasible && isfinite(solution.score) ? solution : nothing
end

function swap_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]
    n = length(solution.calls)

    for i in 1:(n - 1), j in (i + 1):n
        calls = copy_calls(solution.calls)
        calls[i], calls[j] = calls[j], calls[i]
        candidate = feasible_neighbor(mirp, calls)
        candidate !== nothing && push!(candidates, candidate)
    end

    return candidates
end

function relocate_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]
    n = length(solution.calls)

    for i in 1:n
        for j in 1:n
            i == j && continue
            calls = copy_calls(solution.calls)
            call = splice!(calls, i)
            insert!(calls, j, call)
            candidate = feasible_neighbor(mirp, calls)
            candidate !== nothing && push!(candidates, candidate)
        end
    end

    return candidates
end

function replace_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]

    for (i, call) in enumerate(solution.calls)
        for port in mirp.ports
            if port.id == call.port.id || port.type != call.port.type
                continue
            end

            calls = copy_calls(solution.calls)
            calls[i] = Call(port, call.vessel)
            candidate = feasible_neighbor(mirp, calls)
            candidate !== nothing && push!(candidates, candidate)
        end
    end

    return candidates
end

# Insert a short feasible loading/unloading cycle for one vessel.
function insert_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]
    base = evaluate_solution!(mirp, clone_solution(mirp, solution); add_final_inventory_cost = false)
    !base.feasible && return candidates

    for first_call in possible_calls(mirp, base)
        one_call = append_call(mirp, base, first_call.port, first_call.vessel)
        evaluate_solution!(mirp, one_call; add_final_inventory_cost = false)
        !one_call.feasible && continue

        for port in mirp.ports
            if port.type == first_call.port.type
                continue
            end

            two_calls = append_call(mirp, one_call, port, first_call.vessel)
            candidate = evaluate_solution!(mirp, two_calls; add_final_inventory_cost = true)
            candidate.feasible && isfinite(candidate.score) && push!(candidates, candidate)
        end
    end

    return candidates
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

# Remove a call and, when present, the next call of the same vessel to preserve
# the load/unload alternation more often than a single deletion would.
function remove_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]
    n = length(solution.calls)

    for i in 1:n
        remove_indexes = [i]
        j = next_same_vessel_index(solution.calls, i)
        j !== nothing && push!(remove_indexes, j)

        calls = Call[]
        for (k, call) in enumerate(solution.calls)
            k in remove_indexes || push!(calls, copy_call(call))
        end

        candidate = feasible_neighbor(mirp, calls)
        candidate !== nothing && push!(candidates, candidate)
    end

    return candidates
end

# Swap compatible ports between two calls while keeping the assigned vessels.
function swap_port_candidates(mirp::MIRP, solution::Solution)
    candidates = Solution[]
    n = length(solution.calls)

    for i in 1:(n - 1), j in (i + 1):n
        call_i = solution.calls[i]
        call_j = solution.calls[j]
        if call_i.port.type != call_j.port.type || call_i.port.id == call_j.port.id
            continue
        end

        calls = copy_calls(solution.calls)
        calls[i] = Call(call_j.port, call_i.vessel)
        calls[j] = Call(call_i.port, call_j.vessel)
        candidate = feasible_neighbor(mirp, calls)
        candidate !== nothing && push!(candidates, candidate)
    end

    return candidates
end

function neighborhood_candidates(mirp::MIRP, solution::Solution, neighborhood::Symbol)
    if neighborhood == :swap
        return swap_candidates(mirp, solution)
    elseif neighborhood == :relocate
        return relocate_candidates(mirp, solution)
    elseif neighborhood == :replace
        return replace_candidates(mirp, solution)
    elseif neighborhood == :insert
        return insert_candidates(mirp, solution)
    elseif neighborhood == :remove
        return remove_candidates(mirp, solution)
    elseif neighborhood == :swap_port
        return swap_port_candidates(mirp, solution)
    end

    throw(ArgumentError("Unknown neighborhood: $(neighborhood)"))
end

function apply_neighborhood(mirp::MIRP, solution::Solution, neighborhood::Symbol; rng::AbstractRNG = Random.default_rng())
    candidates = neighborhood_candidates(mirp, solution, neighborhood)
    isempty(candidates) && return clone_solution(mirp, solution)
    return rand(rng, candidates)
end

function apply_perturbation(mirp::MIRP, solution::Solution; rng::AbstractRNG = Random.default_rng())
    shuffled = shuffle(rng, collect(NEIGHBORHOODS))
    for neighborhood in shuffled
        candidates = neighborhood_candidates(mirp, solution, neighborhood)
        isempty(candidates) || return rand(rng, candidates)
    end

    return clone_solution(mirp, solution)
end
