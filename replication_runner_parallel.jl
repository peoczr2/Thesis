using Dates
using Distributed

const REPLICATION_RUNNER_PATH = joinpath(@__DIR__, "replication_runner.jl")

include(REPLICATION_RUNNER_PATH)

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
    seeds = parse_seed_arg()
    ils_params = ILSParameters(iterations = ils_iterations)

    jobs = [(instance = instance, seed = seed) for instance in TARGET_INSTANCES for seed in seeds]
    isempty(jobs) && error("No replication jobs to run.")

    requested_jobs = parse_int_arg("jobs", length(jobs))
    requested_jobs > 0 || error("--jobs must be at least 1.")
    worker_count = min(requested_jobs, length(jobs))

    out_dir = "results"
    mkpath(out_dir)
    stamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    csv_path = joinpath(out_dir, "bs_ils_replication_$(run_label)_$(horizon)_$(stamp).csv")

    println("Starting $(length(jobs)) replication jobs on $(worker_count) single-thread Julia workers.")
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
    write_report(report_path, rows, svg_path; N = N, w = w, q = q, ils_params = ils_params)

    println("Wrote $(csv_path)")
    println("Wrote $(svg_path)")
    println("Wrote $(report_path)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main_parallel()
end
