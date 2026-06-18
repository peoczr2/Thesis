using Dates
using Distributed
using Printf
using Statistics

const REPLICATION_RUNNER_PATH = joinpath(@__DIR__, "replication_runner.jl")
const PARALLEL_DEFAULT_SEED_COUNT = 60
const PARALLEL_DEFAULT_MAX_WORKERS = 10

include(REPLICATION_RUNNER_PATH)

function parse_seed_spec(spec::String)
    seeds = Int64[]
    for raw_part in split(spec, ",")
        part = strip(raw_part)
        isempty(part) && continue

        range_parts = split(part, ":")
        if length(range_parts) == 1
            push!(seeds, parse(Int64, range_parts[1]))
        elseif length(range_parts) == 2
            first_seed = parse(Int64, range_parts[1])
            last_seed = parse(Int64, range_parts[2])
            append!(seeds, collect(first_seed:last_seed))
        elseif length(range_parts) == 3
            first_seed = parse(Int64, range_parts[1])
            step = parse(Int64, range_parts[2])
            last_seed = parse(Int64, range_parts[3])
            step == 0 && error("Seed range step cannot be 0 in --seeds=$(spec).")
            append!(seeds, collect(first_seed:step:last_seed))
        else
            error("Could not parse seed specification: $(spec)")
        end
    end

    isempty(seeds) && error("--seeds did not contain any seeds.")
    return seeds
end

function parse_parallel_seed_arg()
    prefix = "--seeds="
    for arg in ARGS
        startswith(arg, prefix) && return parse_seed_spec(replace(arg, prefix => ""))
    end

    seed_count = parse_int_arg("seed-count", PARALLEL_DEFAULT_SEED_COUNT)
    seed_start = parse_int_arg("seed-start", 1)
    seed_count > 0 || error("--seed-count must be at least 1.")
    return collect(seed_start:(seed_start + seed_count - 1))
end

function worker_thread_count(worker::Int64)
    return remotecall_fetch(() -> Threads.nthreads(), worker)
end

function configure_single_thread_worker(worker::Int64)
    threads = worker_thread_count(worker)
    threads == 1 || error("Worker $(worker) has $(threads) Julia threads; expected exactly 1.")

    remotecall_fetch(worker) do
        try
            @eval using LinearAlgebra
            LinearAlgebra.BLAS.set_num_threads(1)
        catch
            nothing
        end
        return nothing
    end
end

function worker_label(worker::Int64)
    return "worker=$(worker), threads=$(worker_thread_count(worker))"
end

function run_instance_parallel(
    worker::Int64,
    instance::Symbol,
    horizon::Int64,
    seed::Int64;
    N::Int64,
    w::Int64,
    q::Int64,
    ils_params::ILSParameters,
)
    return remotecall_fetch(run_instance, worker, instance, horizon, seed; N = N, w = w, q = q, ils_params = ils_params)
end

function ordered_rows(rows_by_index::Dict{Int64, Any})
    return [rows_by_index[index] for index in sort(collect(keys(rows_by_index)))]
end

function summarize_seed_batch(rows)
    grouped = Dict{String, Vector{Any}}()
    for row in rows
        push!(get!(grouped, row.instance, Any[]), row)
    end

    summaries = []
    for instance in sort(collect(keys(grouped)))
        instance_rows = grouped[instance]
        ils_costs = [row.ils_cost for row in instance_rows]
        gaps = [row.gap_pct for row in instance_rows]
        total_times = [row.total_seconds for row in instance_rows]
        push!(
            summaries,
            (
                instance = instance,
                runs = length(instance_rows),
                best_ils = minimum(ils_costs),
                avg_ils = mean(ils_costs),
                best_gap = minimum(gaps),
                avg_gap = mean(gaps),
                avg_total_seconds = mean(total_times),
                total_seconds = sum(total_times),
            ),
        )
    end

    return summaries
end

function write_parallel_report(path::String, rows, figure_path::String; N::Int64, w::Int64, q::Int64, ils_params::ILSParameters, worker_count::Int64)
    horizon = rows[1].horizon
    generated_at = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM")
    summaries = summarize_seed_batch(rows)
    seed_count = length(unique([row.seed for row in rows]))

    open(path, "w") do io
        println(io, "# Beam Search + ILS parallel replication report")
        println(io)
        println(io, "Generated: $(generated_at)")
        println(io)
        println(io, "## Batch settings")
        println(io)
        println(io, "- Horizon: `$(horizon)`")
        println(io, "- Seeds per instance: `$(seed_count)`")
        println(io, "- Total runs: `$(length(rows))`")
        println(io, "- Single-thread workers: `$(worker_count)`")
        println(io, "- Beam nodes per level `N = $(N)`")
        println(io, "- Maximum children per node `w = $(w)`")
        println(io, "- Greedy randomized completions per successor `q = $(q)`")
        println(io, "- ILS iterations: `$(ils_params.iterations)`")
        println(io)
        println(io, "## Per-instance seed summary")
        println(io)
        println(io, "| Instance | Runs | Best ILS | Avg ILS | Best gap | Avg gap | Avg run time (s) | Total run time (s) |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|")
        for row in summaries
            println(io, "| $(row.instance) | $(row.runs) | $(fmt2(row.best_ils)) | $(fmt2(row.avg_ils)) | $(fmt2(row.best_gap))% | $(fmt2(row.avg_gap))% | $(fmt2(row.avg_total_seconds)) | $(fmt2(row.total_seconds)) |")
        end
        println(io)
        println(io, "## Per-run results")
        println(io)
        println(io, "The CSV saved beside this report contains one row per instance/seed run with separate `bs_cost`, `ls_cost`, `ils_cost`, `beam_seconds`, `ls_seconds`, `ils_seconds`, and `total_seconds` columns.")
        println(io)
        println(io, "![Gap comparison]($(basename(figure_path)))")
    end
end

function start_workers(count::Int64)
    workers = addprocs(count; exeflags = "--threads=1")
    for worker in workers
        remotecall_fetch(include, worker, REPLICATION_RUNNER_PATH)
        configure_single_thread_worker(worker)
    end
    return workers
end

function main_parallel()
    horizon = parse_int_arg("horizon", 120)
    N = parse_int_arg("N", PAPER_BS_N)
    w = parse_int_arg("w", PAPER_BS_W)
    q = parse_int_arg("q", PAPER_GRA_Q)
    ils_iterations = parse_int_arg("ils-iterations", PAPER_ILS_PARAMETERS.iterations)
    run_label = parse_string_arg("label", "paper_parallel")
    seeds = parse_parallel_seed_arg()
    ils_params = ILSParameters(iterations = ils_iterations)

    jobs = [(instance = instance, seed = seed) for instance in TARGET_INSTANCES for seed in seeds]
    isempty(jobs) && error("No replication jobs to run.")

    requested_jobs = parse_int_arg("jobs", PARALLEL_DEFAULT_MAX_WORKERS)
    requested_jobs > 0 || error("--jobs must be at least 1.")
    worker_count = min(requested_jobs, PARALLEL_DEFAULT_MAX_WORKERS, length(jobs))

    out_dir = "results"
    mkpath(out_dir)
    stamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    csv_path = joinpath(out_dir, "bs_ils_replication_$(run_label)_$(horizon)_$(stamp).csv")

    println("Starting $(length(jobs)) replication jobs ($(length(TARGET_INSTANCES)) instances x $(length(seeds)) seeds) on $(worker_count) single-thread Julia workers.")
    requested_jobs > PARALLEL_DEFAULT_MAX_WORKERS && println("Requested --jobs=$(requested_jobs); capped at $(PARALLEL_DEFAULT_MAX_WORKERS) workers.")
    flush(stdout)

    added_workers = start_workers(worker_count)
    rows_by_index = Dict{Int64, Any}()
    failures = []

    try
        available_workers = Channel{Int64}(worker_count)
        completions = Channel{Any}(length(jobs))

        for worker in added_workers
            put!(available_workers, worker)
        end

        for (index, job) in enumerate(jobs)
            @async begin
                worker = take!(available_workers)
                try
                    println("Running $(job.instance), horizon=$(horizon), seed=$(job.seed), N=$(N), w=$(w), q=$(q), ils_iterations=$(ils_iterations) ($(worker_label(worker)))")
                    flush(stdout)
                    row = run_instance_parallel(
                        worker,
                        job.instance,
                        horizon,
                        job.seed;
                        N = N,
                        w = w,
                        q = q,
                        ils_params = ils_params,
                    )
                    put!(completions, (ok = true, index = index, row = row, instance = job.instance, seed = job.seed, worker = worker))
                catch err
                    put!(completions, (ok = false, index = index, err = err, backtrace = sprint(showerror, err, catch_backtrace()), instance = job.instance, seed = job.seed, worker = worker))
                finally
                    put!(available_workers, worker)
                end
            end
        end

        for _ in jobs
            result = take!(completions)
            if result.ok
                rows_by_index[result.index] = result.row
                write_results_csv(csv_path, ordered_rows(rows_by_index))
                println("  Finished $(result.instance), seed=$(result.seed): ILS cost=$(fmt2(result.row.ils_cost)), gap=$(fmt2(result.row.gap_pct))%, time=$(fmt2(result.row.total_seconds))s")
                flush(stdout)
            else
                push!(failures, result)
                println(stderr, "  Failed $(result.instance), seed=$(result.seed) on worker $(result.worker):")
                println(stderr, result.backtrace)
                flush(stderr)
            end
        end

        if !isempty(failures)
            error("$(length(failures)) replication job(s) failed. See stderr for details.")
        end
    finally
        rmprocs(added_workers)
    end

    rows = [rows_by_index[index] for index in 1:length(jobs)]
    svg_path = joinpath(out_dir, "bs_ils_replication_gap_$(run_label)_$(horizon)_$(stamp).svg")
    report_path = joinpath(out_dir, "bs_ils_replication_report_$(run_label)_$(horizon)_$(stamp).md")

    write_results_csv(csv_path, rows)
    write_gap_svg(svg_path, rows)
    write_parallel_report(report_path, rows, svg_path; N = N, w = w, q = q, ils_params = ils_params, worker_count = worker_count)

    println("Wrote $(csv_path)")
    println("Wrote $(svg_path)")
    println("Wrote $(report_path)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_parallel()
end
