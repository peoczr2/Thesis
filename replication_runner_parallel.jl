using Dates
using Distributed
using Printf
using Statistics

const REPLICATION_RUNNER_PATH = joinpath(@__DIR__, "replication_runner.jl")
const PARALLEL_DEFAULT_SEED_COUNT = 5
const PARALLEL_DEFAULT_MAX_WORKERS = 10
const PARALLEL_RESULT_HEADERS = [
    :job_index,
    :worker,
    :worker_pid,
    :worker_run,
    :instance,
    :horizon,
    :seed,
    :objective,
    :bs_cost,
    :ls_cost,
    :ils_cost,
    :gap_pct,
    :calls,
    :levels,
    :beam_seconds,
    :ls_seconds,
    :ils_seconds,
    :total_seconds,
    :wall_seconds,
    :worker_rss_mb_before,
    :worker_rss_mb_after,
    :worker_rss_mb_after_gc,
    :started_at,
    :finished_at,
]

include(REPLICATION_RUNNER_PATH)

function parse_bool_arg(name::String, default::Bool)
    prefix = "--$(name)="
    for arg in ARGS
        if startswith(arg, prefix)
            value = lowercase(strip(replace(arg, prefix => "")))
            value in ("1", "true", "yes", "y", "on") && return true
            value in ("0", "false", "no", "n", "off") && return false
            error("Could not parse --$(name)=$(value) as a boolean.")
        end
    end
    return default
end

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

function worker_pid(worker::Int64)
    return remotecall_fetch(() -> getpid(), worker)
end

function worker_rss_mb(worker::Int64)
    return remotecall_fetch(worker) do
        status_path = "/proc/self/status"
        isfile(status_path) || return NaN
        for line in eachline(status_path)
            if startswith(line, "VmRSS:")
                parts = split(line)
                length(parts) >= 2 && return parse(Float64, parts[2]) / 1024.0
            end
        end
        return NaN
    end
end

function cleanup_worker(worker::Int64)
    return remotecall_fetch(worker) do
        GC.gc(true)
        GC.gc(true)
        try
            ccall(:malloc_trim, Cint, (Cint,), 0)
        catch
            nothing
        end
        status_path = "/proc/self/status"
        isfile(status_path) || return NaN
        for line in eachline(status_path)
            if startswith(line, "VmRSS:")
                parts = split(line)
                length(parts) >= 2 && return parse(Float64, parts[2]) / 1024.0
            end
        end
        return NaN
    end
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
    return "worker=$(worker), pid=$(worker_pid(worker)), threads=$(worker_thread_count(worker))"
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

function with_parallel_metadata(row, job_index::Int64, worker::Int64, pid::Integer, worker_run::Int64, wall_seconds::Float64, rss_before::Float64, rss_after::Float64, rss_after_gc::Float64, started_at::String, finished_at::String)
    return merge(
        (
            job_index = job_index,
            worker = worker,
            worker_pid = pid,
            worker_run = worker_run,
        ),
        row,
        (
            wall_seconds = wall_seconds,
            worker_rss_mb_before = rss_before,
            worker_rss_mb_after = rss_after,
            worker_rss_mb_after_gc = rss_after_gc,
            started_at = started_at,
            finished_at = finished_at,
        ),
    )
end

function ordered_rows(rows_by_index::Dict{Int64, Any})
    return [rows_by_index[index] for index in sort(collect(keys(rows_by_index)))]
end

function write_parallel_results_csv(path::String, rows)
    open(path, "w") do io
        println(io, join(string.(PARALLEL_RESULT_HEADERS), ","))
        for row in rows
            println(io, join([csv_escape(getfield(row, header)) for header in PARALLEL_RESULT_HEADERS], ","))
        end
    end
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
        wall_times = [row.wall_seconds for row in instance_rows]
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
                avg_wall_seconds = mean(wall_times),
                total_seconds = sum(total_times),
            ),
        )
    end

    return summaries
end

function write_parallel_report(path::String, rows, figure_path::String; N::Int64, w::Int64, q::Int64, ils_params::ILSParameters, worker_count::Int64, restart_workers_every::Int64, gc_between_runs::Bool)
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
        println(io, "- GC between runs: `$(gc_between_runs)`")
        println(io, "- Restart workers every N runs: `$(restart_workers_every)` (`0` means disabled)")
        println(io, "- Beam nodes per level `N = $(N)`")
        println(io, "- Maximum children per node `w = $(w)`")
        println(io, "- Greedy randomized completions per successor `q = $(q)`")
        println(io, "- ILS iterations: `$(ils_params.iterations)`")
        println(io)
        println(io, "## Per-instance seed summary")
        println(io)
        println(io, "| Instance | Runs | Best ILS | Avg ILS | Best gap | Avg gap | Avg measured time (s) | Avg wall time (s) | Total measured time (s) |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in summaries
            println(io, "| $(row.instance) | $(row.runs) | $(fmt2(row.best_ils)) | $(fmt2(row.avg_ils)) | $(fmt2(row.best_gap))% | $(fmt2(row.avg_gap))% | $(fmt2(row.avg_total_seconds)) | $(fmt2(row.avg_wall_seconds)) | $(fmt2(row.total_seconds)) |")
        end
        println(io)
        println(io, "## Per-run diagnostics")
        println(io)
        println(io, "The CSV saved beside this report contains one row per instance/seed run with separate `bs_cost`, `ls_cost`, `ils_cost`, `beam_seconds`, `ls_seconds`, `ils_seconds`, `total_seconds`, `wall_seconds`, worker pid, worker run count, and worker RSS memory before/after/after-GC columns.")
        println(io)
        println(io, "![Gap comparison]($(basename(figure_path)))")
    end
end

function start_workers(count::Int64)
    ENV["JULIA_NUM_THREADS"] = "1"
    ENV["OPENBLAS_NUM_THREADS"] = "1"
    ENV["OMP_NUM_THREADS"] = "1"
    ENV["MKL_NUM_THREADS"] = "1"
    ENV["VECLIB_MAXIMUM_THREADS"] = "1"
    ENV["NUMEXPR_NUM_THREADS"] = "1"

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
    restart_workers_every = parse_int_arg("restart-workers-every", 0)
    gc_between_runs = parse_bool_arg("gc-between-runs", true)
    restart_workers_every >= 0 || error("--restart-workers-every must be >= 0.")

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
    println("GC between runs: $(gc_between_runs). Restart workers every $(restart_workers_every) run(s); 0 means disabled.")
    flush(stdout)

    active_workers = Set{Int64}()
    worker_runs = Dict{Int64, Int64}()
    added_workers = start_workers(worker_count)
    for worker in added_workers
        push!(active_workers, worker)
        worker_runs[worker] = 0
    end

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
                result = nothing
                try
                    worker_runs[worker] = get(worker_runs, worker, 0) + 1
                    worker_run = worker_runs[worker]
                    pid = worker_pid(worker)
                    rss_before = worker_rss_mb(worker)
                    started_at = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS")

                    println("Running $(job.instance), horizon=$(horizon), seed=$(job.seed), N=$(N), w=$(w), q=$(q), ils_iterations=$(ils_iterations), worker_run=$(worker_run), rss=$(fmt2(rss_before)) MiB ($(worker_label(worker)))")
                    flush(stdout)

                    row = nothing
                    wall_seconds = @elapsed row = run_instance_parallel(
                        worker,
                        job.instance,
                        horizon,
                        job.seed;
                        N = N,
                        w = w,
                        q = q,
                        ils_params = ils_params,
                    )
                    finished_at = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS")
                    rss_after = worker_rss_mb(worker)
                    rss_after_gc = gc_between_runs ? cleanup_worker(worker) : rss_after
                    parallel_row = with_parallel_metadata(row, index, worker, pid, worker_run, wall_seconds, rss_before, rss_after, rss_after_gc, started_at, finished_at)
                    result = (ok = true, index = index, row = parallel_row, instance = job.instance, seed = job.seed, worker = worker, worker_run = worker_run)
                catch err
                    result = (ok = false, index = index, err = err, backtrace = sprint(showerror, err, catch_backtrace()), instance = job.instance, seed = job.seed, worker = worker, worker_run = get(worker_runs, worker, -1))
                    try
                        gc_between_runs && cleanup_worker(worker)
                    catch
                        nothing
                    end
                finally
                    if restart_workers_every > 0 && get(worker_runs, worker, 0) >= restart_workers_every
                        old_worker = worker
                        old_pid = try
                            worker_pid(old_worker)
                        catch
                            -1
                        end
                        println("Restarting worker $(old_worker) pid=$(old_pid) after $(worker_runs[old_worker]) run(s).")
                        flush(stdout)
                        try
                            rmprocs(old_worker)
                        catch err
                            println(stderr, "Could not remove worker $(old_worker): $(err)")
                        end
                        delete!(active_workers, old_worker)
                        delete!(worker_runs, old_worker)

                        replacement = start_workers(1)[1]
                        push!(active_workers, replacement)
                        worker_runs[replacement] = 0
                        worker = replacement
                    end

                    put!(available_workers, worker)
                    put!(completions, result)
                end
            end
        end

        for _ in jobs
            result = take!(completions)
            if result.ok
                rows_by_index[result.index] = result.row
                write_parallel_results_csv(csv_path, ordered_rows(rows_by_index))
                println("  Finished $(result.instance), seed=$(result.seed), worker_run=$(result.worker_run): ILS cost=$(fmt2(result.row.ils_cost)), gap=$(fmt2(result.row.gap_pct))%, measured=$(fmt2(result.row.total_seconds))s, wall=$(fmt2(result.row.wall_seconds))s, rss_after_gc=$(fmt2(result.row.worker_rss_mb_after_gc)) MiB")
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
        if !isempty(active_workers)
            rmprocs(collect(active_workers))
        end
    end

    rows = [rows_by_index[index] for index in 1:length(jobs)]
    svg_path = joinpath(out_dir, "bs_ils_replication_gap_$(run_label)_$(horizon)_$(stamp).svg")
    report_path = joinpath(out_dir, "bs_ils_replication_report_$(run_label)_$(horizon)_$(stamp).md")

    write_parallel_results_csv(csv_path, rows)
    write_gap_svg(svg_path, rows)
    write_parallel_report(report_path, rows, svg_path; N = N, w = w, q = q, ils_params = ils_params, worker_count = worker_count, restart_workers_every = restart_workers_every, gc_between_runs = gc_between_runs)

    println("Wrote $(csv_path)")
    println("Wrote $(svg_path)")
    println("Wrote $(report_path)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_parallel()
end
