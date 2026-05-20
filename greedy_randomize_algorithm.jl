# TODO: dont forget that the node has to be copied, not just ref copy
function deterministic_eval(node::Solution, time_horizon)
    t = node.calls[-1].service_time_port
    while t <= time_horizon
        for port_call::Call in node.last_occ_ports
            if port_call !== nothing
                curr_next_violation_time = t - port_call.service_time_port + port_call.port.rates[t]
                port.inventory_level = port.port.rates[t]
                if port.inventory_level > port.port.max_amt
                    port.next_violation_time = t
                end
            end
        end
    end
    return node
end

function stochastic_eval(node::Solution)
    # evaluate the solution in a stochastic way, for example by using a random seed
    return score
end