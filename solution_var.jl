using MIRPLib

# A call is the atomic routing decision: one vessel visiting one port.
# Evaluation also stores predecessor/successor links and cumulative costs here.
mutable struct Call
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

function Call(port::Port, vessel::Vessel)
    return Call(
        port,
        vessel,
        nothing,
        nothing,
        nothing,
        nothing,
        0,
        0,
        0,
        0.0,
        typemax(Int64),
        0.0,
        0.0,
        0.0,
    )
end

# A solution is a call sequence plus evaluator caches for the latest rebuilt state.
mutable struct Solution
    calls::Vector{Call}
    score::Float64
    last_occ_ports::Vector{Union{Nothing, Call}}
    last_occ_vessels::Vector{Union{Nothing, Call}}
    vessel_inventory::Vector{Float64}
    vessel_time::Vector{Int64}
    port_inventory::Vector{Float64}
    port_time::Vector{Int64}
    port_next_violation::Vector{Int64}
    feasible::Bool
end

function Solution(mirp::MIRP)
    return Solution(
        Call[],
        Inf,
        Union{Nothing, Call}[nothing for _ in mirp.ports],
        Union{Nothing, Call}[nothing for _ in mirp.vessels],
        Float64[vessel.inventory for vessel in mirp.vessels],
        Int64[vessel.first_time for vessel in mirp.vessels],
        Float64[port.inventory for port in mirp.ports],
        zeros(Int64, length(mirp.ports)),
        fill(typemax(Int64), length(mirp.ports)),
        true,
    )
end

function Solution(mirp::MIRP, calls::Vector{Call})
    solution = Solution(mirp)
    solution.calls = calls
    return solution
end

function copy_call(call::Call)
    return Call(call.port, call.vessel)
end

function copy_evaluated_call(call::Call)
    copied = copy_call(call)
    copied.last_service_time_vessel = call.last_service_time_vessel
    copied.service_time_port = call.service_time_port
    copied.num_vessels_in_port = call.num_vessels_in_port
    copied.inventory_level = call.inventory_level
    copied.next_violation_time = call.next_violation_time
    copied.acc_routing_costs = call.acc_routing_costs
    copied.acc_inventory_costs = call.acc_inventory_costs
    copied.acc_total_costs = call.acc_total_costs
    return copied
end

function copy_calls(calls::Vector{Call})
    return [copy_call(call) for call in calls]
end

function clone_solution(mirp::MIRP, solution::Solution)
    return Solution(mirp, copy_calls(solution.calls))
end

function append_call(mirp::MIRP, solution::Solution, port::Port, vessel::Vessel)
    calls = copy_calls(solution.calls)
    push!(calls, Call(port, vessel))
    return Solution(mirp, calls)
end

# TODO: check this function
"""
Hard copy a solution with rewired internal call links.
"""
function clone_evaluated_solution(mirp::MIRP, solution::Solution)
    old_to_new = IdDict{Call, Call}()
    calls = Call[]

    for call in solution.calls
        copied = copy_evaluated_call(call)
        old_to_new[call] = copied
        push!(calls, copied)
    end

    for call in solution.calls
        copied = old_to_new[call]
        copied.last_occ_vessel = call.last_occ_vessel === nothing ? nothing : old_to_new[call.last_occ_vessel]
        copied.last_occ_port = call.last_occ_port === nothing ? nothing : old_to_new[call.last_occ_port]
        copied.next_occ_vessel = call.next_occ_vessel === nothing ? nothing : old_to_new[call.next_occ_vessel]
        copied.next_occ_port = call.next_occ_port === nothing ? nothing : old_to_new[call.next_occ_port]
    end

    cloned = Solution(mirp, calls)
    cloned.score = solution.score
    cloned.last_occ_ports = Union{Nothing, Call}[
        call === nothing ? nothing : old_to_new[call] for call in solution.last_occ_ports
    ]
    cloned.last_occ_vessels = Union{Nothing, Call}[
        call === nothing ? nothing : old_to_new[call] for call in solution.last_occ_vessels
    ]
    cloned.vessel_inventory = copy(solution.vessel_inventory)
    cloned.vessel_time = copy(solution.vessel_time)
    cloned.port_inventory = copy(solution.port_inventory)
    cloned.port_time = copy(solution.port_time)
    cloned.port_next_violation = copy(solution.port_next_violation)
    cloned.feasible = solution.feasible
    return cloned
end

function solution_signature(solution::Solution)
    return Tuple((call.port.id, call.vessel.id) for call in solution.calls)
end

function Base.show(io::IO, call::Call)
    print(io, "(", call.port, ", ", call.vessel, ")")
end
