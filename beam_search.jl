# Evaluation Function
function evaluate(node, q)
    scores.add(deterministic_eval(node))
    for i in 1:(q - 1)
        scores.add(stochastic_eval(node))
    end
    return scores
end

# Check if already existing node
function exist()
    #???????????????? they say at Beam Search levels they dont want solution with the same score, 
    #but like they phrase in such way it suggest a continues selection process and not taking the top N nodes
    # without duplicates

end

# Keep track of the best N nodes
function keep_best_N_nodes(nodes)

end


function beam_search(N, q, w)
    beam_nodes = [empty_node]

# Iteration
while found_successor
    found_successor = false
    # Node Expansion
    new successors = [beam_nodes.size * w]
    for( node in beam_nodes)
        for( call in possbile_calls)
            successors.add(create_new_node(node, call))
            found_successor = true
        end
    end

    # Successor Evaluation
    for( successor in successors)
        scores = evaluate(successor, q)
        successor.score = median(scores)
        keep_best_N_nodes(scores)
    end

    # Beam Selection
    beam_nodes = sort(successors, by = x -> x.score, rev = true)[1:N]
end

# Output
