using Dates
using HTTP
using JSON3
using Random
using Sockets

const SERVER_URL = get(ENV, "QUEUE_SERVER", "http://127.0.0.1:8000")
const WORKER_ID = get(ENV, "WORKER_ID", "$(gethostname())-$(getpid())")
const MAX_RETRIES = parse(Int, get(ENV, "QUEUE_MAX_RETRIES", "8"))
const RETRY_SECONDS = parse(Float64, get(ENV, "QUEUE_RETRY_SECONDS", "10"))

function request_with_retry(fn, description::String)
    for attempt in 1:MAX_RETRIES
        try
            return fn()
        catch err
            println("[$(now())] $(description) failed on attempt $(attempt)/$(MAX_RETRIES): $(err)")
            if attempt == MAX_RETRIES
                rethrow()
            end
            sleep(RETRY_SECONDS)
        end
    end
end

function get_task()
    encoded_worker = HTTP.escapeuri(WORKER_ID)
    response = request_with_retry("GET /get_task") do
        HTTP.get("$(SERVER_URL)/get_task?worker_id=$(encoded_worker)"; readtimeout = 60)
    end
    return JSON3.read(String(response.body))
end

function complete_task(instance::String, seed::Int; runtime_seconds::Union{Nothing, Float64} = nothing)
    payload = Dict(
        "instance" => instance,
        "seed" => seed,
        "worker_id" => WORKER_ID,
        "status" => "completed",
        "runtime_seconds" => runtime_seconds,
    )
    body = JSON3.write(payload)
    response = request_with_retry("POST /complete_task") do
        HTTP.post(
            "$(SERVER_URL)/complete_task",
            ["Content-Type" => "application/json"],
            body;
            readtimeout = 60,
        )
    end
    return JSON3.read(String(response.body))
end

function run_dummy_optimization(instance::String, seed::Int)
    println("Starting C-BEAT optimization | Instance: $(instance) | Seed: $(seed)")
    started = time()

    # Replace this block later with the real Julia replication call, for example:
    # include(joinpath(@__DIR__, "..", "replication_runner.jl"))
    # row = run_instance(Symbol(instance), 120, seed; scorer = :gra)
    sleep(rand(2:5))

    return time() - started
end

function main()
    println("Worker $(WORKER_ID) connecting to $(SERVER_URL)")

    while true
        task = get_task()
        if haskey(task, :message) && String(task.message) == "done"
            println("No pending tasks remain. Worker $(WORKER_ID) shutting down gracefully.")
            break
        end

        instance = String(task.instance)
        seed = Int(task.seed)
        runtime_seconds = run_dummy_optimization(instance, seed)
        response = complete_task(instance, seed; runtime_seconds = runtime_seconds)
        println("Completed $(instance), seed=$(seed): $(response)")
    end
end

main()
