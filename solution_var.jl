struct Call
    port::Port
    vessel::Vessel
    
    last_occ_vessel::Union{Nothing, Call}
    last_occ_port::Union{Nothing, Call}
    next_occ_vessel::Union{Nothing, Call}
    next_occ_port::Union{Nothing, Call}

    last_service_time_vessel::Int64
    service_time_port::Int64
    num_vessels_in_port::Int64
    inventory_level::Float64
    next_violation_time::Int64
    acc_routing_costs::Float64
    acc_inventory_costs::Float64
    acc_total_costs::Float64
end

struct Solution{P, V}
    calls::Vector{Call} = []
    score::Float64 = 0.0
    last_occ_ports::Vector{Union{Nothing, Call}} = Vector{Union{Nothing, Call}}(undef, MIRP.ports)
    last_occ_vessels::Vector{Union{Nothing, Call}} = Vector{Union{Nothing, Call}}(undef, MIRP.vessels)
end
