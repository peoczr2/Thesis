function has_evaluated_calls(solution::Solution)
    return all(call -> call.service_time_port > 0, solution.calls)
end

# TODO: this is kind of useless
function neighbor_source_solution(mirp::MIRP, solution::Solution)
    return solution.feasible && has_evaluated_calls(solution) ?
        solution :
        evaluate_solution!(mirp, clone_solution(mirp, solution); add_final_inventory_cost = true)
end

"""
Scores the neighbor. Return score=Inf if the change is infeasible.
Does not modify solution.
"""
function score_swap!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    for k in i:length(solution.calls)
        call = k == i ? solution.calls[j] : k == j ? solution.calls[i] : solution.calls[k]
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function relocated_call_at(calls::Vector{Call}, i::Int64, j::Int64, k::Int64)
    if i < j
        if k < i || k > j
            return calls[k]
        elseif k == j
            return calls[i]
        else
            return calls[k + 1]
        end
    else
        if k < j || k > i
            return calls[k]
        elseif k == j
            return calls[i]
        else
            return calls[k - 1]
        end
    end
end

function score_relocate!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    prefix_length = min(i, j) - 1
    reset_evaluator_to_prefix!(evaluator, mirp, solution, prefix_length)
    for k in (prefix_length + 1):length(solution.calls)
        call = relocated_call_at(solution.calls, i, j, k)
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_replace!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    port::Port,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    old_call = solution.calls[i]
    status = evaluate_call!(evaluator, mirp, port, old_call.vessel)
    status === :infeasible && return Inf
    if status !== :discarded
        for k in (i + 1):length(solution.calls)
            call = solution.calls[k]
            status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
            status === :fulfilled && continue
            status === :discarded && break
            return Inf
        end
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_insert!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    first_port::Port,
    vessel::Vessel,
    second_port::Port,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, length(solution.calls))
    status = evaluate_call!(evaluator, mirp, first_port, vessel)
    status === :infeasible && return Inf
    status === :discarded && return Inf
    status = evaluate_call!(evaluator, mirp, second_port, vessel)
    status === :infeasible && return Inf
    return final_evaluate_score(evaluator, mirp)
end

function score_remove!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    first_index::Int64,
    second_index::Union{Nothing, Int64} = nothing,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, first_index - 1)
    for k in first_index:length(solution.calls)
        (k == first_index || k == second_index) && continue
        call = solution.calls[k]
        status = evaluate_call!(evaluator, mirp, call.port, call.vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end

function score_swap_port!(
    evaluator::CallEvaluator,
    mirp::MIRP,
    solution::Solution,
    i::Int64,
    j::Int64,
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, i - 1)
    call_i = solution.calls[i]
    call_j = solution.calls[j]
    for k in i:length(solution.calls)
        if k == i
            port, vessel = call_j.port, call_i.vessel
        elseif k == j
            port, vessel = call_i.port, call_j.vessel
        else
            call = solution.calls[k]
            port, vessel = call.port, call.vessel
        end
        status = evaluate_call!(evaluator, mirp, port, vessel)
        status === :fulfilled && continue
        status === :discarded && break
        return Inf
    end
    return final_evaluate_score(evaluator, mirp)
end


"""
Modifies the solution by evaluating the calls from a certain index to the end, and returns the modified solution. It uses the existing call list.
"""
function evaluate_suffix_neighbor!(
    mirp::MIRP,
    solution::Solution,
    prefix_length::Int64,
    add_final_inventory_cost::Bool = true;
    evaluator::CallEvaluator = CallEvaluator(mirp),
)
    reset_evaluator_to_prefix!(evaluator, mirp, solution, prefix_length)
    reset_solution_to_evaluated_prefix!(mirp, solution, prefix_length)

    i = prefix_length + 1
    while i <= length(solution.calls)
        status = evaluate_call_i!(mirp, solution, evaluator, i)
        if status === :fulfilled
            i += 1
        elseif status === :discarded
            break
        else
            return nothing
        end
    end

    add_final_inventory_cost && finalize_evaluation!(mirp, solution)
    return solution.feasible && isfinite(solution.score) ? solution : nothing
end


