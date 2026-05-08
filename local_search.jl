




# Randomized Variable Neighborhood Descent (RVND)
function local_search(initial_solution, neigbourhoods)
    current_solution = initial_solution
    found_better_solution = true

    while found_better_solution
        found_better_solution = false

        shuffle!(neigbourhoods)
        for neighborhood in neigbourhoods
            new_solution = apply_neighborhood(current_solution, neighborhood)

            if current_solution.score < new_solution.score
                current_solution = new_solution
                found_better_solution = true
                break
            end
        end
    end
    
    return current_solution
end