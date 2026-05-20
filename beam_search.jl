# Evaluation Function
# Given a node evaluate and update its score, and return any other generated solutions that overall might be good candidates
function evaluate(node::Solution, q)
    full_solutions::Vector{Solution} = []
    full_solutions.add(evaluate_solution(deterministic_eval(node)))
    for i in 1:(q - 1)
        full_solutions.add(stochastic_eval(node))
    end
    # update the original solution's score
    node.score = median([s.score for s in full_solutions]) # TODO: make it more efficient
    return full_solutions
end

function is_feasible(node::Solution, port::Port, vessel::Vessel)
    # feasible if the vessel travels between production and consumption ports
    if node.last_occ_vessels[vessel.id] != nothing
        if node.last_occ_vessels[vessel.id].port.type != port.type
            return true
        end
    end
end
# TODO: dont forget to change the last_occ_vessels when the new solution is created
# given a partial solution(node), return all possible calls that can be added to the solution
function possbile_calls(node::Solution)
    calls::Vector{Call} = []
    for port in ports
        for vessel in vessels
            if is_feasible(node, port, vessel)
                push!(calls, Call(port, vessel))
            end
        end
    end
    return calls
end
function create_new_node(node::Solution, call::Call)
    new_node = deepcopy(node)
    push!(new_node.calls, call)
    new_node.last_occ_ports[call.port.id] = call
    new_node.last_occ_vessels[call.vessel.id] = call
    return new_node
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


function beam_search(N, w, q)
    beam_nodes = [Solution()]

    # Iteration
    while found_successor
        found_successor = false
        # Node Expansion
        successors = Vector{Solution}(undef, beam_nodes.size * w)
        for node in beam_nodes
            for call in possbile_calls(node)
                successors.add(create_new_node(node, call))
                found_successor = true
            end
        end

        # Successor Evaluation
        for successor in successors
            all_eval_sol = evaluate(successor, q)
            keep_best_N_solutions(all_eval_sol)
        end

        # TODO: max w successors per node, but not sure how to do it
        # Beam Selection                TODO: might be smart to do top(successors, N) as not whole vector needed to be sorted
        beam_nodes = sort(successors, by = x -> x.score, rev = true)[1:N]
    end

    # Output
end