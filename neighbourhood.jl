
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

function ordered_indices(rng::AbstractRNG, n::Int64, randomize::Bool)
    return randomize ? randperm(rng, n) : Base.OneTo(n)
end

function ordered_items(rng::AbstractRNG, items, randomize::Bool)
    return randomize ? shuffle(rng, collect(items)) : items
end

function accepted_neighbor(candidate::Union{Nothing, Solution}, current_score::Union{Nothing, Float64})
    candidate === nothing && return nothing
    current_score === nothing && return candidate
    return candidate.score + EPS < current_score ? candidate : nothing
end

function swap_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    n = length(solution.calls)

    for i in ordered_indices(rng, max(n - 1, 0), randomize)
        for j in ordered_indices(rng, n, randomize)
            i < j || continue

            calls = copy_calls(solution.calls)
            calls[i], calls[j] = calls[j], calls[i]
            candidate = accepted_neighbor(feasible_neighbor(mirp, calls), current_score)
            candidate !== nothing && return candidate
        end
    end

    return nothing
end

function relocate_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    n = length(solution.calls)

    for i in ordered_indices(rng, n, randomize)
        for j in ordered_indices(rng, n, randomize)
            i == j && continue

            calls = copy_calls(solution.calls)
            call = splice!(calls, i)
            insert!(calls, j, call)
            candidate = accepted_neighbor(feasible_neighbor(mirp, calls), current_score)
            candidate !== nothing && return candidate
        end
    end

    return nothing
end

function replace_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    for i in ordered_indices(rng, length(solution.calls), randomize)
        call = solution.calls[i]

        for port in ordered_items(rng, mirp.ports, randomize)
            if port.id == call.port.id || port.type != call.port.type
                continue
            end

            calls = copy_calls(solution.calls)
            calls[i] = Call(port, call.vessel)
            candidate = accepted_neighbor(feasible_neighbor(mirp, calls), current_score)
            candidate !== nothing && return candidate
        end
    end

    return nothing
end

# Insert a short feasible loading/unloading cycle for one vessel.
function insert_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    base = evaluate_solution!(mirp, clone_solution(mirp, solution); add_final_inventory_cost = false)
    !base.feasible && return nothing

    for first_port in ordered_items(rng, mirp.ports, randomize)
        for vessel in ordered_items(rng, mirp.vessels, randomize)
            is_feasible(base, first_port, vessel) || continue

            one_call = append_call(mirp, base, first_port, vessel)
            evaluate_solution!(mirp, one_call; add_final_inventory_cost = false)
            !one_call.feasible && continue

            for port in ordered_items(rng, mirp.ports, randomize)
                port.type == first_port.type && continue

                two_calls = append_call(mirp, one_call, port, vessel)
                candidate = evaluate_solution!(mirp, two_calls; add_final_inventory_cost = true)
                if candidate.feasible && isfinite(candidate.score)
                    candidate = accepted_neighbor(candidate, current_score)
                    candidate !== nothing && return candidate
                end
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

# Remove a call and, when present, the next call of the same vessel to preserve
# the load/unload alternation more often than a single deletion would.
function remove_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    n = length(solution.calls)

    for i in ordered_indices(rng, n, randomize)
        remove_indexes = [i]
        j = next_same_vessel_index(solution.calls, i)
        j !== nothing && push!(remove_indexes, j)

        calls = Call[]
        for (k, call) in enumerate(solution.calls)
            k in remove_indexes || push!(calls, copy_call(call))
        end

        candidate = accepted_neighbor(feasible_neighbor(mirp, calls), current_score)
        candidate !== nothing && return candidate
    end

    return nothing
end

# Swap compatible ports between two calls while keeping the assigned vessels.
function swap_port_neighbor(
    mirp::MIRP,
    solution::Solution,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
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

            calls = copy_calls(solution.calls)
            calls[i] = Call(call_j.port, call_i.vessel)
            calls[j] = Call(call_i.port, call_j.vessel)
            candidate = accepted_neighbor(feasible_neighbor(mirp, calls), current_score)
            candidate !== nothing && return candidate
        end
    end

    return nothing
end

function neighborhood_neighbor(
    mirp::MIRP,
    solution::Solution,
    neighborhood::Symbol,
    current_score::Union{Nothing, Float64} = nothing;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    if neighborhood == :swap
        return swap_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :relocate
        return relocate_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :replace
        return replace_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :insert
        return insert_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :remove
        return remove_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :swap_port
        return swap_port_neighbor(mirp, solution, current_score; rng = rng, randomize = randomize)
    end

    throw(ArgumentError("Unknown neighborhood: $(neighborhood)"))
end

function apply_neighborhood(
    mirp::MIRP,
    solution::Solution,
    neighborhood::Symbol;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    candidate = neighborhood_neighbor(mirp, solution, neighborhood; rng = rng, randomize = randomize)
    return candidate === nothing ? clone_solution(mirp, solution) : candidate
end

function apply_perturbation(
    mirp::MIRP,
    solution::Solution;
    rng::AbstractRNG = Random.default_rng(),
    randomize::Bool = true,
)
    neighborhood_order = randomize ? shuffle(rng, collect(NEIGHBORHOODS)) : collect(NEIGHBORHOODS)
    for neighborhood in neighborhood_order
        candidate = neighborhood_neighbor(mirp, solution, neighborhood; rng = rng, randomize = randomize)
        candidate !== nothing && return candidate
    end

    return clone_solution(mirp, solution)
end
