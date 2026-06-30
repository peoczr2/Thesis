using Dates
using HTTP
using JSON3
using Random
using Sockets

const SERVER_URL = get(ENV, "QUEUE_SERVER", "http://127.0.0.1:8000")
const WORKER_ID = get(ENV, "WORKER_ID", "$(gethostname())-$(getpid())")
const MAX_RETRIES = parse(Int, get(ENV, "QUEUE_MAX_RETRIES", "8"))
const RETRY_SECONDS = parse(Float64, get(ENV, "QUEUE_RETRY_SECONDS", "10"))
const REQUEST_HEADERS = ["ngrok-skip-browser-warning" => "true"]

include(joinpath(@__DIR__, "..", "replication_runner.jl"))

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
        HTTP.get("$(SERVER_URL)/get_task?worker_id=$(encoded_worker)", REQUEST_HEADERS; readtimeout = 60)
    end
    return JSON3.read(String(response.body))
end

function complete_task(
    instance::String,
    horizon::Int,
    seed::Int,
    scorer::String;
    runtime_seconds::Union{Nothing, Float64} = nothing,
    result::Union{Nothing, Dict{String, Any}} = nothing,
)
    payload = Dict(
        "instance" => instance,
        "horizon" => horizon,
        "seed" => seed,
        "scorer" => scorer,
        "worker_id" => WORKER_ID,
        "status" => "completed",
        "result" => result,
        "runtime_seconds" => runtime_seconds,
    )
    body = JSON3.write(payload)
    response = request_with_retry("POST /complete_task") do
        HTTP.post(
            "$(SERVER_URL)/complete_task",
            ["Content-Type" => "application/json"; REQUEST_HEADERS],
            body;
            readtimeout = 60,
        )
    end
    return JSON3.read(String(response.body))
end

function truncate_error(message::String)
    return length(message) > 12000 ? first(message, 12000) : message
end

function fail_task(
    instance::String,
    horizon::Int,
    seed::Int,
    scorer::String,
    error_message::String;
    runtime_seconds::Union{Nothing, Float64} = nothing,
)
    payload = Dict(
        "instance" => instance,
        "horizon" => horizon,
        "seed" => seed,
        "scorer" => scorer,
        "worker_id" => WORKER_ID,
        "error_message" => truncate_error(error_message),
        "runtime_seconds" => runtime_seconds,
    )
    body = JSON3.write(payload)
    response = request_with_retry("POST /fail_task") do
        HTTP.post(
            "$(SERVER_URL)/fail_task",
            ["Content-Type" => "application/json"; REQUEST_HEADERS],
            body;
            readtimeout = 60,
        )
    end
    return JSON3.read(String(response.body))
end

function row_payload(row)
    return Dict(String(key) => getfield(row, key) for key in keys(row))
end

function run_optimization(instance::String, horizon::Int, seed::Int, scorer::String)
    println("Starting BS-ILS | Instance: $(instance) | Horizon: $(horizon) | Seed: $(seed) | Scorer: $(scorer)")
    started = time()

    row = run_instance(Symbol(instance), horizon, seed; scorer = Symbol(scorer))

    return time() - started, row_payload(row)
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
        horizon = Int(task.horizon)
        seed = Int(task.seed)
        scorer = String(task.scorer)
        task_started = time()

        try
            runtime_seconds, result = run_optimization(instance, horizon, seed, scorer)
            response = complete_task(instance, horizon, seed, scorer; runtime_seconds = runtime_seconds, result = result)
            println("Completed $(instance), horizon=$(horizon), seed=$(seed), scorer=$(scorer): $(response)")
        catch err
            runtime_seconds = time() - task_started
            error_message = sprint(showerror, err, catch_backtrace())
            println("Failed $(instance), horizon=$(horizon), seed=$(seed), scorer=$(scorer):")
            println(error_message)

            try
                response = fail_task(instance, horizon, seed, scorer, error_message; runtime_seconds = runtime_seconds)
                println("Reported failure for $(instance), horizon=$(horizon), seed=$(seed), scorer=$(scorer): $(response)")
            catch report_err
                println("Could not report failure to queue server:")
                println(sprint(showerror, report_err, catch_backtrace()))
                rethrow(report_err)
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
