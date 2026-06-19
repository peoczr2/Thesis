using Dates
using Printf
using Random
using MIRPLib

include("solution_var.jl")
include("evaluate.jl")
include("evaluate_neighbor.jl")
include("greedy_randomize_algorithm.jl")
include("beam_search.jl")
include("neighbourhood.jl")
include("local_search.jl")
include("iterated_local_search.jl")

const PAPER_BS_N = 1000
const PAPER_BS_W = 2
const PAPER_GRA_Q = 3
const PAPER_TIME_LIMIT_SECONDS = 90_000.0

# Instance subset requested for the replication run.
const TARGET_INSTANCES = [
    :LR1_DR02_VC01_V6a,
    :LR1_DR02_VC02_V6a,
    :LR1_DR02_VC03_V7a,
    :LR1_DR02_VC03_V8a,
    :LR1_DR02_VC04_V8a,
    :LR1_DR02_VC05_V8a,
]

# Paper table values used as the reference line in generated reports and plots.
const PAPER_RESULTS = Dict(
    120 => Dict(
        :LR1_DR02_VC01_V6a => (obj = 33809.00, best = 33808.95, avg = 33808.95, best_gap = 0.00, avg_gap = 0.00),
        :LR1_DR02_VC02_V6a => (obj = 74982.00, best = 74981.65, avg = 74981.65, best_gap = 0.00, avg_gap = 0.00),
        :LR1_DR02_VC03_V7a => (obj = 40446.00, best = 40340.01, avg = 40418.33, best_gap = -0.26, avg_gap = -0.07),
        :LR1_DR02_VC03_V8a => (obj = 43721.00, best = 43721.43, avg = 43933.34, best_gap = 0.00, avg_gap = 0.48),
        :LR1_DR02_VC04_V8a => (obj = 41657.00, best = 41708.65, avg = 41781.14, best_gap = 0.12, avg_gap = 0.30),
        :LR1_DR02_VC05_V8a => (obj = 36659.00, best = 36536.62, avg = 36615.31, best_gap = -0.33, avg_gap = -0.12),
    ),
    180 => Dict(
        :LR1_DR02_VC01_V6a => (obj = 52167.00, best = 52167.21, avg = 52167.21, best_gap = 0.00, avg_gap = 0.00),
        :LR1_DR02_VC02_V6a => (obj = 129372.00, best = 129372.06, avg = 129730.83, best_gap = 0.00, avg_gap = 0.28),
        :LR1_DR02_VC03_V7a => (obj = 60547.00, best = 60546.80, avg = 61389.49, best_gap = 0.00, avg_gap = 1.37),
        :LR1_DR02_VC03_V8a => (obj = 68153.00, best = 70143.11, avg = 70976.93, best_gap = 2.84, avg_gap = 3.98),
        :LR1_DR02_VC04_V8a => (obj = 66017.00, best = 66064.00, avg = 66275.61, best_gap = 0.07, avg_gap = 0.39),
        :LR1_DR02_VC05_V8a => (obj = 58619.00, best = 58090.14, avg = 58250.16, best_gap = -0.91, avg_gap = -0.63),
    ),
    360 => Dict(
        :LR1_DR02_VC01_V6a => (obj = 108141.00, best = 108141.00, avg = 108141.00, best_gap = 0.00, avg_gap = 0.00),
        :LR1_DR02_VC02_V6a => (obj = 283031.00, best = 281910.11, avg = 283857.52, best_gap = -0.40, avg_gap = 0.29),
        :LR1_DR02_VC03_V7a => (obj = 124282.00, best = 124315.00, avg = 126345.86, best_gap = 0.03, avg_gap = 1.63),
        :LR1_DR02_VC03_V8a => (obj = 141166.00, best = 142461.48, avg = 145925.59, best_gap = 0.91, avg_gap = 3.26),
        :LR1_DR02_VC04_V8a => (obj = 138693.00, best = 139072.01, avg = 139203.18, best_gap = 0.27, avg_gap = 0.37),
        :LR1_DR02_VC05_V8a => (obj = 122598.00, best = 122430.70, avg = 122751.13, best_gap = -0.14, avg_gap = 0.12),
    ),
)

function parse_int_arg(name::String, default::Int64)
    prefix = "--$(name)="
    for arg in ARGS
        startswith(arg, prefix) && return parse(Int64, replace(arg, prefix => ""))
    end
    return default
end

function parse_string_arg(name::String, default::String)
    prefix = "--$(name)="
    for arg in ARGS
        startswith(arg, prefix) && return replace(arg, prefix => "")
    end
    return default
end

function parse_seed_arg()
    prefix = "--seeds="
    for arg in ARGS
        if startswith(arg, prefix)
            return [parse(Int64, seed) for seed in split(replace(arg, prefix => ""), ",")]
        end
    end
    return [1]
end

function gap(cost::Float64, reference::Float64)
    return 100.0 * (cost - reference) / reference
end

# One full replication pipeline for an instance: BS, RVND, then ILS.
function run_instance(
    instance::Symbol,
    horizon::Int64,
    seed::Int64;
    N::Int64 = PAPER_BS_N,
    w::Int64 = PAPER_BS_W,
    q::Int64 = PAPER_GRA_Q,
    ils_params::ILSParameters = PAPER_ILS_PARAMETERS,
    include_waits::Bool = true,
    wait_periods = WAIT_PERIODS,
)
    mirp = loadMIRP(instance, horizon)
    mirp === nothing && error("Could not load $(instance) with horizon $(horizon).")
    rng = MersenneTwister(seed)

    beam_elapsed = @elapsed beam_result = beam_search(
        mirp;
        N = N,
        w = w,
        q = q,
        rng = rng,
        include_waits = include_waits,
        wait_periods = wait_periods,
    )

    ls_elapsed = @elapsed ls_solution = local_search(mirp, beam_result.best_solution; rng = rng)
    ils_elapsed = @elapsed ils_solution = iterated_local_search(
        mirp,
        ls_solution;
        rng = rng,
        params = ils_params,
    )

    reference = isfinite(mirp.ub) ? mirp.ub : PAPER_RESULTS[horizon][instance].obj
    return (
        instance = String(instance),
        horizon = horizon,
        seed = seed,
        objective = reference,
        bs_cost = beam_result.best_solution.score,
        ls_cost = ls_solution.score,
        ils_cost = ils_solution.score,
        gap_pct = gap(ils_solution.score, reference),
        calls = length(ils_solution.calls),
        levels = beam_result.levels,
        beam_seconds = beam_elapsed,
        ls_seconds = ls_elapsed,
        ils_seconds = ils_elapsed,
        total_seconds = beam_elapsed + ls_elapsed + ils_elapsed,
    )
end

function csv_escape(value)
    text = string(value)
    if occursin(",", text) || occursin("\"", text)
        return "\"" * replace(text, "\"" => "\"\"") * "\""
    end
    return text
end

function write_results_csv(path::String, rows)
    headers = [
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
    ]

    open(path, "w") do io
        println(io, join(string.(headers), ","))
        for row in rows
            println(io, join([csv_escape(getfield(row, header)) for header in headers], ","))
        end
    end
end

function fmt2(x)
    return @sprintf("%.2f", x)
end

# Minimal SVG writer to keep the replication report self-contained.
function write_gap_svg(path::String, rows)
    width = 980
    height = 420
    margin_left = 90
    margin_bottom = 80
    plot_width = width - margin_left - 30
    plot_height = height - 50 - margin_bottom
    max_gap = maximum(abs(row.gap_pct) for row in rows)
    max_gap = max(max_gap, maximum(abs(PAPER_RESULTS[rows[1].horizon][Symbol(row.instance)].best_gap) for row in rows), 1.0)
    scale = plot_height / (2.0 * max_gap)
    zero_y = 50 + plot_height / 2
    group_width = plot_width / length(rows)
    bar_width = min(28.0, group_width / 4)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width / 2)\" y=\"24\" text-anchor=\"middle\" font-family=\"Arial\" font-size=\"18\">Replication gap vs paper best gap</text>")
        println(io, "<line x1=\"$margin_left\" y1=\"$zero_y\" x2=\"$(width - 30)\" y2=\"$zero_y\" stroke=\"#444\"/>")
        println(io, "<text x=\"18\" y=\"$(zero_y + 4)\" font-family=\"Arial\" font-size=\"12\">0%</text>")

        for (i, row) in enumerate(rows)
            x = margin_left + (i - 0.5) * group_width
            paper_gap = PAPER_RESULTS[row.horizon][Symbol(row.instance)].best_gap
            values = [(paper_gap, "#4c78a8", "paper"), (row.gap_pct, "#f58518", "rep")]
            for (offset, item) in enumerate(values)
                value, color, _ = item
                bar_height = abs(value) * scale
                y = value >= 0 ? zero_y - bar_height : zero_y
                bx = x + (offset - 1.5) * (bar_width + 4)
                println(io, "<rect x=\"$bx\" y=\"$y\" width=\"$bar_width\" height=\"$bar_height\" fill=\"$color\"/>")
            end
            label = replace(row.instance, "LR1_DR02_" => "")
            println(io, "<text x=\"$x\" y=\"$(height - 45)\" text-anchor=\"middle\" font-family=\"Arial\" font-size=\"11\" transform=\"rotate(35 $x,$(height - 45))\">$label</text>")
        end

        println(io, "<rect x=\"760\" y=\"42\" width=\"14\" height=\"14\" fill=\"#4c78a8\"/><text x=\"780\" y=\"54\" font-family=\"Arial\" font-size=\"12\">Paper best gap</text>")
        println(io, "<rect x=\"760\" y=\"62\" width=\"14\" height=\"14\" fill=\"#f58518\"/><text x=\"780\" y=\"74\" font-family=\"Arial\" font-size=\"12\">Replication gap</text>")
        println(io, "</svg>")
    end
end

# Markdown report writer matching the paper-style result table plus a gap figure.
function write_report(path::String, rows, figure_path::String; N::Int64 = PAPER_BS_N, w::Int64 = PAPER_BS_W, q::Int64 = PAPER_GRA_Q, ils_params::ILSParameters = PAPER_ILS_PARAMETERS)
    horizon = rows[1].horizon
    generated_at = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM")
    open(path, "w") do io
        println(io, "# Beam Search + ILS replication report")
        println(io)
        println(io, "Generated: $(generated_at)")
        println(io)
        println(io, "## Paper settings used")
        println(io)
        println(io, "- Beam nodes per level `N = $(N)`")
        println(io, "- Maximum children per node `w = $(w)`")
        println(io, "- Greedy randomized completions per successor `q = $(q)`")
        println(io, "- ILS parameters from Table 4: initial SA probability `$(ils_params.initial_probability)`, final SA probability `$(ils_params.final_probability)`, `$(ils_params.iterations)` iterations, restore after `$(ils_params.restore_after)` non-improving accepted moves, `$(ils_params.perturbations)` perturbations")
        println(io, "- Horizon run in this batch: `$(horizon)`")
        println(io)
        println(io, "## Implementation notes")
        println(io)
        println(io, "The paper does not specify every tie-break, random sampling, and simulated annealing temperature detail. This replication follows the described structure: BS evaluates partial solutions with one deterministic and `q - 1` randomized greedy completions, keeps unique scored nodes, applies RVND neighborhoods, then runs ILS. The local-search phase is applied to the BS incumbent before ILS; applying RVND to every generated complete solution was left as a documented deviation because the paper's implementation details and pruning rules are not fully specified.")
        println(io)
        println(io, "## Results")
        println(io)
        println(io, "| Instance | Obj | Paper best | Rep BS | Rep LS | Rep ILS | Rep gap | Time (s) |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|")
        for row in rows
            target = PAPER_RESULTS[row.horizon][Symbol(row.instance)]
            println(io, "| $(row.instance) | $(fmt2(row.objective)) | $(fmt2(target.best)) | $(fmt2(row.bs_cost)) | $(fmt2(row.ls_cost)) | $(fmt2(row.ils_cost)) | $(fmt2(row.gap_pct))% | $(fmt2(row.total_seconds)) |")
        end
        println(io)
        println(io, "![Gap comparison]($(basename(figure_path)))")
    end
end

# CLI entry point for paper-parameter and smoke replication batches.
function main()
    horizon = parse_int_arg("horizon", 120)
    N = parse_int_arg("N", PAPER_BS_N)
    w = parse_int_arg("w", PAPER_BS_W)
    q = parse_int_arg("q", PAPER_GRA_Q)
    ils_iterations = parse_int_arg("ils-iterations", PAPER_ILS_PARAMETERS.iterations)
    run_label = parse_string_arg("label", "paper")
    seeds = parse_seed_arg()
    ils_params = ILSParameters(iterations = ils_iterations)
    out_dir = "results"
    mkpath(out_dir)
    stamp = Dates.format(now(), dateformat"yyyymmdd_HHMMSS")
    csv_path = joinpath(out_dir, "bs_ils_replication_$(run_label)_$(horizon)_$(stamp).csv")

    rows = []
    for instance in TARGET_INSTANCES
        for seed in seeds
            println("Running $(instance), horizon=$(horizon), seed=$(seed), N=$(N), w=$(w), q=$(q), ils_iterations=$(ils_iterations)")
            flush(stdout)
            row = run_instance(instance, horizon, seed; N = N, w = w, q = q, ils_params = ils_params)
            push!(rows, row)
            write_results_csv(csv_path, rows)
            println("  ILS cost=$(fmt2(row.ils_cost)), gap=$(fmt2(row.gap_pct))%, time=$(fmt2(row.total_seconds))s")
            flush(stdout)
        end
    end

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
    main()
end
