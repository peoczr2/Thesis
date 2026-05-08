


function iterated_local_search(initial_solution, iterations)
    current_solution = initial_solution
    new_solution = initial_solution
    for i in 1:iterations
        new_solution = apply_perturbation(current_solution)
        new_solution = apply_perturbation(new_solution)
        new_solution = local_search(new_solution)

        if sim_annealing_criterion(new_solution, current_solution)
            if new_solution.score <= current_solution.score
                no_improvement += 1
            end
            current_solution = new_solution
        else
            # TODO: could increase the no_improvement counter here as well, but not sure if the original paper did it
        end
        
        # When this counter exceeds the allowednumber of non-improving iterations,
        # the solution is restored, and the counter resets.
        if no_improvement >= max_no_improvement
            current_solution = best_solution
            no_improvement = 0
        end

        # I am just guessing that this needs to be tracked
        if current_solution.score < best_solution.score
            best_solution = current_solution
        end
    end

    return best_solution
end