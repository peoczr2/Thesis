
function distance(p1::Port, p2::Port)
    return sqrt((p1.x - p2.x)^2 + (p1.y - p2.y)^2)
end

function evaluate_call()

function evaluate_solution(MIRP, solution::Solution, C::Matrix{Matrix{Float64}}, P::Matrix{Float64})
    last_occ_vessels = Vector{Union{Nothing, Call}}(undef, length(MIRP.vessels))
    last_occ_ports = Vector{Union{Nothing, Call}}(undef, length(MIRP.ports))
    for call in solution.calls
        call.last_occ_vessel = last_occ_vessels[call.vessel.id]     # last_occ_vessel
                                                                    # last_service_time_vessel
        call.last_service_time_vessel = call.last_occ_vessel !== nothing ? call.last_occ_vessel.service_time_port : 0
        if call.last_occ_vessel !== nothing
            call.last_occ_vessel.next_occ_vessel = call             # next_occ_vessel
        end
        call.last_occ_port = last_occ_ports[call.port.id    ]       # last_occ_port
        if call.last_occ_port !== nothing
            call.last_occ_port.next_occ_port = call                 # next_occ_port
        end
        # vessel arrival time at port TODO: there is an initial_port specified in the dataset
        if call.last_occ_vessel !== nothing
            arrival_time = call.vessel.class.travel_times[call.port.id][call.last_occ_vessel.port.id] + call.last_service_time_vessel
        else
            arrival_time = 0
        end
        
        if call.last_occ_port !== nothing                           # service_time_port
            if call.last_occ_port.service_time_port >= arrival_time
                if call.last_occ_port.num_vessels_in_port < call.port.berth_limit
                    call.service_time_port = call.last_occ_port.service_time_port
                    call.num_vessels_in_port = call.last_occ_port.num_vessels_in_port + 1
                else
                    call.service_time_port = call.last_occ_port.service_time_port + 1
                    call.num_vessels_in_port = 1
                end
            else
                call.service_time_port = arrival_time
                call.num_vessels_in_port = 1
            end
        else
            call.service_time_port = 0
            call.num_vessels_in_port = 1
        end

        last_occ_vessels[call.vessel.id] = call
        last_occ_ports[call.port.id] = call

        if call.port.type == "consumer"
            prev_inv = call.last_occ_port !== nothing ? call.last_occ_port.inventory_level : 0
            new_inv =  prev_inv + call.port.rates[call.service_time_port] - call.vessel.class.capacity
            call.inventory_level = min(new_inv, call.port.max_amt)
            alpha = max(new_inv - call.port.max_amt, 0)
        else
        end

        
        call.acc_inventory_costs += P[call.port.id][call.service_time_port] * alpha
        call.acc_routing_costs += C[call.vessel.class.id][call.port.id][call.last_occ_vessel !== nothing ? call.last_occ_vessel.port.id : call.vessel.initial_port.id]
        call.acc_total_costs = call.acc_routing_costs + call.acc_inventory_costs
    end
    solution.score = solution.calls[-1].acc_total_costs
    return solution
end