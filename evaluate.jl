
using Random
using MIRPLib

const EPS = 1.0e-9

function horizon(mirp::MIRP)
    return mirp.metadata.n_periods
end

function period_index(values::AbstractVector, t::Int64)
    return clamp(t, 1, length(values))
end

function violation_price(mirp::MIRP, port::Port, t::Int64)
    price = port.prices[period_index(port.prices, t)]
    return price == 0.0 ? mirp.metadata.spot_market_price : price
end

function clear_call_state!(call::Call)
    call.last_occ_vessel = nothing
    call.last_occ_port = nothing
    call.next_occ_vessel = nothing
    call.next_occ_port = nothing
    call.last_service_time_vessel = 0
    call.service_time_port = 0
    call.num_vessels_in_port = 0
    call.inventory_level = 0.0
    call.next_violation_time = typemax(Int64)
    call.acc_routing_costs = 0.0
    call.acc_inventory_costs = 0.0
    call.acc_total_costs = 0.0
    return call
end

function reset_solution_state!(solution::Solution, mirp::MIRP)
    time_horizon = horizon(mirp)
    solution.score = Inf
    solution.last_occ_ports = Union{Nothing, Call}[nothing for _ in mirp.ports]
    solution.last_occ_vessels = Union{Nothing, Call}[nothing for _ in mirp.vessels]
    solution.vessel_inventory = Float64[vessel.inventory for vessel in mirp.vessels]
    solution.vessel_time = Int64[vessel.first_time for vessel in mirp.vessels]
    solution.port_inventory = Float64[port.inventory for port in mirp.ports]
    solution.port_time = zeros(Int64, length(mirp.ports))
    solution.port_next_violation = Int64[
        next_violation_period(port, Float64(port.inventory), 0, time_horizon) for port in mirp.ports
    ]
    solution.feasible = true

    for call in solution.calls
        clear_call_state!(call)
    end

    return solution
end

function advance_inventory(mirp::MIRP, port::Port, inventory::Float64, from_t::Int64, to_t::Int64)
    penalty = 0.0

    if to_t <= from_t
        return inventory, penalty
    end

    for t in (from_t + 1):to_t
        rate = port.rates[period_index(port.rates, t)]

        if port.type == :loading
            inventory += rate
            if inventory > port.capacity
                excess = inventory - port.capacity
                penalty += excess * violation_price(mirp, port, t)
                inventory = Float64(port.capacity)
            end
        else
            inventory -= rate
            if inventory < 0.0
                shortage = -inventory
                penalty += shortage * violation_price(mirp, port, t)
                inventory = 0.0
            end
        end
    end

    return inventory, penalty
end

function next_violation_period(port::Port, inventory::Float64, from_t::Int64, time_horizon::Int64)
    if from_t >= time_horizon
        return time_horizon + 1
    end

    for t in (from_t + 1):time_horizon
        rate = port.rates[period_index(port.rates, t)]
        inventory += port.type == :loading ? rate : -rate

        if inventory > port.capacity || inventory < 0.0
            return t
        end
    end

    return time_horizon + 1
end



"""
Checks if the vessels last port and the port param has different types.t.
"""
function is_feasible(node::Solution, port::Port, vessel::Vessel)
    last_call = node.last_occ_vessels[vessel.id]
    last_port = last_call === nothing ? vessel.initial_port : last_call.port # TODO: how to handle when a vessel has not yet visited any port

    if last_call === nothing && last_port.id == port.id
        return true
    end

    return last_port.type != port.type
end

function inventory_after_service_period(mirp::MIRP, call::Call, inventory::Float64, cargo::Float64, service_time::Int64)
    rate = call.port.rates[period_index(call.port.rates, service_time)] # TODO: i guess this calculates the accumulated rate from last service time until the current service time

    # TODO: hmm, it should be empty i think, so maybe if its then have like a run time error or something so that we can catch if there is a bug in inventory tracking
    if call.port.type == :loading
        load_amount = max(0.0, call.vessel.class.capacity - cargo)
        return inventory + rate - load_amount
    end

    unload_amount = cargo
    return inventory - rate + unload_amount
end

# TODO: i think there is no such a thing as inventory_feasibility, as the heuristic should actively seek a service_time where there is enough inventory or enough free capacity
function service_is_inventory_feasible(mirp::MIRP, call::Call, inventory::Float64, cargo::Float64, service_time::Int64)
    inventory_after = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
    return 0.0 - EPS <= inventory_after <= call.port.capacity + EPS
end

function first_service_time(
    mirp::MIRP,
    solution::Solution,
    call::Call,
    berth_use::Dict{Int64, Int64},
    arrival::Int64,
    time_horizon::Int64,
)
    port_id = call.port.id
    inventory_start = solution.port_inventory[port_id]
    from_t = solution.port_time[port_id]
    cargo = solution.vessel_inventory[call.vessel.id]

    for t in max(1, arrival):time_horizon
        vessels_in_port = get(berth_use, t, 0)
        if vessels_in_port >= call.port.berth_limit
            continue
        end

        inventory_at_t, _ = advance_inventory(mirp, call.port, inventory_start, from_t, t - 1)
        if service_is_inventory_feasible(mirp, call, inventory_at_t, cargo, t)
            return t, vessels_in_port + 1
        end
    end

    return time_horizon + 1, 0
end

# TODO: check this
function route_cost(mirp::MIRP, vessel::Vessel, from_port::Port, to_port::Port, cargo_before::Float64)
    travel_cost = mirp.distances[from_port.id, to_port.id] * vessel.class.travel_cost_km

    if from_port.type == :unloading && to_port.type == :loading && cargo_before <= EPS
        travel_cost *= max(0.0, 1.0 - vessel.class.discount_empty)
    end

    return travel_cost + to_port.fee
end

function apply_service!(mirp::MIRP, solution::Solution, call::Call, service_time::Int64)
    port_id = call.port.id
    vessel_id = call.vessel.id
    inventory = solution.port_inventory[port_id]
    cargo = solution.vessel_inventory[vessel_id]
    penalty = 0.0

    if call.port.type == :loading
        load_amount = max(0.0, call.vessel.class.capacity - cargo)
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
        cargo += load_amount

        if inventory < 0.0
            penalty += -inventory * violation_price(mirp, call.port, service_time)
            inventory = 0.0
        end
    else
        unload_amount = cargo
        inventory = inventory_after_service_period(mirp, call, inventory, cargo, service_time)
        cargo = 0.0

        if inventory > call.port.capacity
            penalty += (inventory - call.port.capacity) * violation_price(mirp, call.port, service_time)
            inventory = Float64(call.port.capacity)
        end
    end

    solution.port_inventory[port_id] = inventory
    solution.vessel_inventory[vessel_id] = cargo
    return penalty
end

"""
Appends a call to a solutions hard copy and evaluate this new solution efficently. Maybe return nothing if the call is not feasible
"""
function append_evaluated_call(mirp::MIRP, solution::Solution, port::Port, vessel::Vessel)
    new_solution = clone_evaluated_solution(mirp, solution) # TODO: check if its a hard copy
    call = Call(port, vessel)

    # TODO: in theory this should not happen, and maybe use throwing an error if for some reason it does, or return nothing or false
    if !is_feasible(new_solution, port, vessel)
        push!(new_solution.calls, call)
        new_solution.feasible = false
        new_solution.score = Inf
        return new_solution
    end

    time_horizon = horizon(mirp)
    port_id = port.id
    vessel_id = vessel.id
    last_occ_vessel = new_solution.last_occ_vessels[vessel_id]
    last_occ_port = new_solution.last_occ_ports[port_id]
    from_port = last_occ_vessel === nothing ? vessel.initial_port : last_occ_vessel.port
    last_service_time_vessel = last_occ_vessel === nothing ? vessel.first_time : last_occ_vessel.service_time_port
    arrival = max(1, last_service_time_vessel + vessel.class.travel_times[from_port.id, port_id])

    # TODO: this is not efficient, it should be stored already what is a ports actual berth use at least have efficient jumping call to call and not doing it in O(n) time
    berth_use = Dict{Int64, Int64}()
    for existing_call in new_solution.calls
        if existing_call.port.id == port_id && existing_call.service_time_port > 0
            berth_use[existing_call.service_time_port] = get(berth_use, existing_call.service_time_port, 0) + 1
        end
    end

    service_time, vessels_in_port = first_service_time(
        mirp,
        new_solution,
        call,
        berth_use,
        arrival,
        time_horizon,
    )

    # TODO: this kind of solution infeasibility does not exist i think, as if the call would happen after the time horizon then just ignore it. But do not make the whole solution infeasible, or maybe name it differently as to signal that the last call can not happen
    if service_time > time_horizon
        push!(new_solution.calls, call)
        new_solution.feasible = false
        new_solution.score = Inf
        return new_solution
    end

    routing_cost = isempty(new_solution.calls) ? 0.0 : new_solution.calls[end].acc_routing_costs # TODO: maybe it could accept that its initialized with 0.0
    inventory_cost = isempty(new_solution.calls) ? 0.0 : new_solution.calls[end].acc_inventory_costs
    inventory, penalty = advance_inventory(
        mirp,
        port,
        new_solution.port_inventory[port_id],
        new_solution.port_time[port_id],
        service_time - 1,
    )
    new_solution.port_inventory[port_id] = inventory
    inventory_cost += penalty

    cargo_before = new_solution.vessel_inventory[vessel_id]
    routing_cost += route_cost(mirp, vessel, from_port, port, cargo_before)
    inventory_cost += apply_service!(mirp, new_solution, call, service_time)

    call.last_occ_vessel = last_occ_vessel
    call.last_occ_port = last_occ_port
    if last_occ_vessel !== nothing
        last_occ_vessel.next_occ_vessel = call
    end
    if last_occ_port !== nothing
        last_occ_port.next_occ_port = call
    end

    call.last_service_time_vessel = last_service_time_vessel
    call.service_time_port = service_time
    call.num_vessels_in_port = vessels_in_port
    call.inventory_level = new_solution.port_inventory[port_id]
    call.next_violation_time = next_violation_period(port, call.inventory_level, service_time, time_horizon)
    new_solution.port_next_violation[port_id] = call.next_violation_time
    call.acc_routing_costs = routing_cost
    call.acc_inventory_costs = inventory_cost
    call.acc_total_costs = routing_cost + inventory_cost

    push!(new_solution.calls, call)
    new_solution.last_occ_ports[port_id] = call
    new_solution.last_occ_vessels[vessel_id] = call
    new_solution.port_time[port_id] = service_time
    new_solution.vessel_time[vessel_id] = service_time
    new_solution.score = routing_cost + inventory_cost
    new_solution.feasible = true
    return new_solution
end

function evaluate_solution!(mirp::MIRP, solution::Solution; add_final_inventory_cost::Bool = true)
    reset_solution_state!(solution, mirp)

    time_horizon = horizon(mirp)
    berth_use = [Dict{Int64, Int64}() for _ in mirp.ports]
    routing_cost = 0.0
    inventory_cost = 0.0

    for call in solution.calls
        if !is_feasible(solution, call.port, call.vessel)
            solution.feasible = false
            solution.score = Inf
            return solution
        end

        port_id = call.port.id
        vessel_id = call.vessel.id
        last_occ_vessel = solution.last_occ_vessels[vessel_id]
        last_occ_port = solution.last_occ_ports[port_id]
        from_port = last_occ_vessel === nothing ? call.vessel.initial_port : last_occ_vessel.port
        last_service_time_vessel = last_occ_vessel === nothing ? call.vessel.first_time : last_occ_vessel.service_time_port
        arrival = max(1, last_service_time_vessel + call.vessel.class.travel_times[from_port.id, port_id])
        service_time, vessels_in_port = first_service_time(
            mirp,
            solution,
            call,
            berth_use[port_id],
            arrival,
            time_horizon,
        )

        if service_time > time_horizon
            solution.feasible = false
            solution.score = Inf
            return solution
        end

        inventory, penalty = advance_inventory(
            mirp,
            call.port,
            solution.port_inventory[port_id],
            solution.port_time[port_id],
            service_time - 1,
        )
        solution.port_inventory[port_id] = inventory
        inventory_cost += penalty

        cargo_before = solution.vessel_inventory[vessel_id]
        routing_cost += route_cost(mirp, call.vessel, from_port, call.port, cargo_before)
        inventory_cost += apply_service!(mirp, solution, call, service_time)

        call.last_occ_vessel = last_occ_vessel
        call.last_occ_port = last_occ_port
        if last_occ_vessel !== nothing
            last_occ_vessel.next_occ_vessel = call
        end
        if last_occ_port !== nothing
            last_occ_port.next_occ_port = call
        end

        call.last_service_time_vessel = last_service_time_vessel
        call.service_time_port = service_time
        call.num_vessels_in_port = vessels_in_port
        call.inventory_level = solution.port_inventory[port_id]
        call.next_violation_time = next_violation_period(call.port, call.inventory_level, service_time, time_horizon)
        solution.port_next_violation[port_id] = call.next_violation_time
        call.acc_routing_costs = routing_cost
        call.acc_inventory_costs = inventory_cost
        call.acc_total_costs = routing_cost + inventory_cost

        solution.last_occ_ports[port_id] = call
        solution.last_occ_vessels[vessel_id] = call
        solution.port_time[port_id] = service_time
        solution.vessel_time[vessel_id] = service_time
        berth_use[port_id][service_time] = vessels_in_port
    end

    if add_final_inventory_cost
        for port in mirp.ports
            inventory, penalty = advance_inventory(
                mirp,
                port,
                solution.port_inventory[port.id],
                solution.port_time[port.id],
                time_horizon,
            )
            solution.port_inventory[port.id] = inventory
            solution.port_time[port.id] = time_horizon
            solution.port_next_violation[port.id] = time_horizon + 1
            inventory_cost += penalty
        end
    end

    solution.score = routing_cost + inventory_cost
    solution.feasible = true
    return solution
end