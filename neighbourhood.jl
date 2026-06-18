
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

            candidate = accepted_neighbor(evaluate_swap(mirp, solution, i, j), current_score)
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

            candidate = accepted_neighbor(evaluate_relocate(mirp, solution, i, j), current_score)
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

            candidate = accepted_neighbor(evaluate_replace(mirp, solution, i, port), current_score)
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
    base = clone_evaluated_prefix(mirp, solution, length(solution.calls))
    berth_use = berth_use_by_port(mirp, base)

    for first_port in ordered_items(rng, mirp.ports, randomize)
        for vessel in ordered_items(rng, mirp.vessels, randomize)
            is_feasible(base, first_port, vessel) || continue
            candidate_append(mirp, base, first_port, vessel, berth_use[first_port.id]) === nothing && continue

            for port in ordered_items(rng, mirp.ports, randomize)
                port.type == first_port.type && continue

                candidate = accepted_neighbor(evaluate_insert(mirp, solution, first_port, vessel, port), current_score)
                candidate !== nothing && return candidate
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
        j = next_same_vessel_index(solution.calls, i)
        candidate = accepted_neighbor(evaluate_remove(mirp, solution, i, j), current_score)
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

            candidate = accepted_neighbor(evaluate_swap_port(mirp, solution, i, j), current_score)
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
    source_solution = neighbor_source_solution(mirp, solution)

    if neighborhood == :swap
        return swap_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :relocate
        return relocate_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :replace
        return replace_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :insert
        return insert_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :remove
        return remove_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
    elseif neighborhood == :swap_port
        return swap_port_neighbor(mirp, source_solution, current_score; rng = rng, randomize = randomize)
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
