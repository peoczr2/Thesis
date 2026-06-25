using Dates
using Printf
using Statistics

const DEFAULT_GRA_CSV = "results/bs_ils_replication_mlcmp_gra_120_20260623_091648.csv"
const DEFAULT_LINEAR_CSV = "results/bs_ils_replication_mlcmp_linear_120_20260623_093113.csv"

function parse_string_arg(name::String, default::String)
    prefix = "--$(name)="
    for arg in ARGS
        startswith(arg, prefix) && return replace(arg, prefix => "")
    end
    return default
end

function parse_row_value(value::AbstractString)
    stripped = strip(value)
    isempty(stripped) && return stripped
    parsed_float = tryparse(Float64, stripped)
    parsed_float !== nothing && return parsed_float
    return stripped
end

function read_simple_csv(path::String)
    rows = NamedTuple[]
    open(path, "r") do io
        header_line = readline(io)
        headers = Symbol.(split(header_line, ","))
        for line in eachline(io)
            isempty(strip(line)) && continue
            values = split(line, ",")
            length(values) == length(headers) || error("Could not parse $(path): column count mismatch in line $(line)")
            push!(rows, NamedTuple{Tuple(headers)}(Tuple(parse_row_value(value) for value in values)))
        end
    end
    return rows
end

function keyed_rows(rows)
    return Dict((String(row.instance), Int(row.seed)) => row for row in rows)
end

function fmt2(value)
    return @sprintf("%.2f", value)
end

function fmt3(value)
    return @sprintf("%.3f", value)
end

function pct_change(new_value, old_value)
    abs(old_value) < 1.0e-9 && return NaN
    return 100.0 * (new_value - old_value) / old_value
end

function write_table_csv(path::String, rows::Vector{<:NamedTuple})
    isempty(rows) && return
    headers = collect(keys(rows[1]))
    open(path, "w") do io
        println(io, join(string.(headers), ","))
        for row in rows
            println(io, join([string(getfield(row, header)) for header in headers], ","))
        end
    end
end

function stage_comparison_rows(gra_rows, linear_rows)
    gra_by_key = keyed_rows(gra_rows)
    linear_by_key = keyed_rows(linear_rows)
    rows = NamedTuple[]

    for key in sort(collect(intersect(keys(gra_by_key), keys(linear_by_key))))
        gra = gra_by_key[key]
        linear = linear_by_key[key]
        push!(rows, (
            instance = key[1],
            seed = key[2],
            gra_beam_seconds = gra.beam_seconds,
            linear_beam_seconds = linear.beam_seconds,
            beam_change_pct = pct_change(linear.beam_seconds, gra.beam_seconds),
            gra_ls_seconds = gra.ls_seconds,
            linear_ls_seconds = linear.ls_seconds,
            ls_change_pct = pct_change(linear.ls_seconds, gra.ls_seconds),
            gra_ils_seconds = gra.ils_seconds,
            linear_ils_seconds = linear.ils_seconds,
            ils_change_pct = pct_change(linear.ils_seconds, gra.ils_seconds),
            gra_total_seconds = gra.total_seconds,
            linear_total_seconds = linear.total_seconds,
            total_change_pct = pct_change(linear.total_seconds, gra.total_seconds),
            gra_beam_share_pct = 100.0 * gra.beam_seconds / gra.total_seconds,
            linear_beam_share_pct = 100.0 * linear.beam_seconds / linear.total_seconds,
            linear_ls_ils_extra_seconds = (linear.ls_seconds + linear.ils_seconds) - (gra.ls_seconds + gra.ils_seconds),
        ))
    end

    return rows
end

function objective_comparison_rows(gra_rows, linear_rows)
    gra_by_key = keyed_rows(gra_rows)
    linear_by_key = keyed_rows(linear_rows)
    rows = NamedTuple[]

    for key in sort(collect(intersect(keys(gra_by_key), keys(linear_by_key))))
        gra = gra_by_key[key]
        linear = linear_by_key[key]
        push!(rows, (
            instance = key[1],
            seed = key[2],
            objective_reference = gra.objective,
            gra_bs_cost = gra.bs_cost,
            linear_bs_cost = linear.bs_cost,
            bs_delta = linear.bs_cost - gra.bs_cost,
            gra_ls_cost = gra.ls_cost,
            linear_ls_cost = linear.ls_cost,
            ls_delta = linear.ls_cost - gra.ls_cost,
            gra_ils_cost = gra.ils_cost,
            linear_ils_cost = linear.ils_cost,
            ils_delta = linear.ils_cost - gra.ils_cost,
            gra_gap_pct = gra.gap_pct,
            linear_gap_pct = linear.gap_pct,
            gap_delta_points = linear.gap_pct - gra.gap_pct,
            gra_ls_gain = gra.bs_cost - gra.ls_cost,
            linear_ls_gain = linear.bs_cost - linear.ls_cost,
            gra_ils_gain = gra.ls_cost - gra.ils_cost,
            linear_ils_gain = linear.ls_cost - linear.ils_cost,
            gra_pool = Int(gra.beam_pool),
            linear_pool = Int(linear.beam_pool),
            gra_ls_improvements = Int(gra.ls_improvements),
            linear_ls_improvements = Int(linear.ls_improvements),
        ))
    end

    return rows
end

function write_stage_markdown(io, rows)
    println(io, "| Instance | BS change | LS change | ILS change | Total change | Linear extra LS+ILS (s) | Linear beam share |")
    println(io, "|---|---:|---:|---:|---:|---:|---:|")
    for row in rows
        println(io, "| $(row.instance) | $(fmt2(row.beam_change_pct))% | $(fmt2(row.ls_change_pct))% | $(fmt2(row.ils_change_pct))% | $(fmt2(row.total_change_pct))% | $(fmt2(row.linear_ls_ils_extra_seconds)) | $(fmt2(row.linear_beam_share_pct))% |")
    end
end

function write_objective_markdown(io, rows)
    println(io, "| Instance | GRA BS | Linear BS | BS delta | GRA ILS | Linear ILS | ILS delta | Gap delta | Linear LS gain |")
    println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for row in rows
        println(io, "| $(row.instance) | $(fmt2(row.gra_bs_cost)) | $(fmt2(row.linear_bs_cost)) | $(fmt2(row.bs_delta)) | $(fmt2(row.gra_ils_cost)) | $(fmt2(row.linear_ils_cost)) | $(fmt2(row.ils_delta)) | $(fmt3(row.gap_delta_points)) pp | $(fmt2(row.linear_ls_gain)) |")
    end
end

function write_equal_beam_markdown(io, objective_rows, stage_rows)
    by_instance = Dict(row.instance => row for row in stage_rows)
    equalish = [row for row in objective_rows if abs(row.bs_delta) <= 1.0e-4]
    if isempty(equalish)
        println(io, "No instances had effectively identical beam-search incumbent costs.")
        return
    end

    println(io, "| Instance | Same BS cost | Beam time change | Total time change | Interpretation |")
    println(io, "|---|---:|---:|---:|---|")
    for row in equalish
        stage = by_instance[row.instance]
        interpretation = stage.beam_change_pct < 0 ?
            "same construction quality with faster beam phase" :
            "same construction quality but slower construction"
        println(io, "| $(row.instance) | $(fmt2(row.linear_bs_cost)) | $(fmt2(stage.beam_change_pct))% | $(fmt2(stage.total_change_pct))% | $(interpretation) |")
    end
end

function write_report(path::String, stage_rows, objective_rows, gra_csv::String, linear_csv::String)
    generated_at = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM")
    avg_beam_change = mean(row.beam_change_pct for row in stage_rows)
    avg_total_change = mean(row.total_change_pct for row in stage_rows)
    beam_faster = count(row -> row.beam_change_pct < 0, stage_rows)
    final_better = count(row -> row.ils_delta < -1.0e-6, objective_rows)
    same_bs = count(row -> abs(row.bs_delta) <= 1.0e-4, objective_rows)
    sum_gra_time = sum(row.gra_total_seconds for row in stage_rows)
    sum_linear_time = sum(row.linear_total_seconds for row in stage_rows)

    open(path, "w") do io
        println(io, "# Linear surrogate analysis plan and current evidence")
        println(io)
        println(io, "Generated: $(generated_at)")
        println(io)
        println(io, "Input GRA CSV: `$(gra_csv)`")
        println(io, "Input linear CSV: `$(linear_csv)`")
        println(io)
        println(io, "## What should be measured")
        println(io)
        println(io, "The linear scorer should not be judged only by final ILS cost or only by total runtime. It changes the construction phase and also changes the pool of completed solutions that LS and ILS receive. The useful measurements are therefore:")
        println(io)
        println(io, "- Construction quality: `bs_cost`, beam levels, and whether the same or better BS incumbent is found.")
        println(io, "- Construction runtime: `beam_seconds` and the beam share of total runtime.")
        println(io, "- Improvement workload: `ls_seconds`, `ils_seconds`, `ls_improvements`, and local-search gain from BS to LS.")
        println(io, "- Final quality cascade: whether a different BS pool gives LS/ILS a better basin, even when the immediate BS incumbent is not better.")
        println(io, "- Pool diversity: final-pool objective spread, unique route signatures, call-count spread, and pairwise route distance from diagnostic runs.")
        println(io, "- Prediction behavior: per-level training samples, when the model becomes active, how many successors are predicted versus GRA-completed, and prediction error on the shortlisted nodes.")
        println(io)
        println(io, "## Current headline")
        println(io)
        println(io, "Across the current six horizon-120 runs, linear made the beam phase faster on $(beam_faster)/$(length(stage_rows)) instances, with an average beam-time change of $(fmt2(avg_beam_change))%. However, total measured runtime increased by $(fmt2(avg_total_change))% on average because LS and ILS became much more expensive. Final ILS cost improved on $(final_better)/$(length(objective_rows)) instances, and $(same_bs)/$(length(objective_rows)) instances had the same BS incumbent under GRA and linear.")
        println(io)
        println(io, "The thesis point is stronger if phrased as: the linear model is a learned construction-phase filter that can preserve or improve construction quality while reducing GRA completions, but its downstream value depends on controlling the size and difficulty of the LS/ILS pool.")
        println(io)
        println(io, "## Stage-time comparison")
        println(io)
        write_stage_markdown(io, stage_rows)
        println(io)
        println(io, "Sum measured time: GRA $(fmt2(sum_gra_time)) s, linear $(fmt2(sum_linear_time)) s.")
        println(io)
        println(io, "## Objective cascade")
        println(io)
        write_objective_markdown(io, objective_rows)
        println(io)
        vc02_delta = first(row.ils_delta for row in objective_rows if occursin("VC02", row.instance))
        println(io, "The VC02 result is the key positive quality example: linear improves the final ILS objective by $(fmt2(vc02_delta)) despite not changing the algorithm after construction. This means the learned scorer can redirect the search toward a different basin, and LS/ILS can inherit that advantage.")
        println(io)
        println(io, "## Same beam incumbent cases")
        println(io)
        write_equal_beam_markdown(io, objective_rows, stage_rows)
        println(io)
        println(io, "These cases are useful for the thesis because they isolate the acceleration claim. If the BS incumbent is the same, then objective quality is held constant at construction time; any runtime difference shows whether the predictive scorer reduces construction work and whether downstream improvement dominates the total runtime.")
        println(io)
        println(io, "## Why can the objective improve?")
        println(io)
        println(io, "The beam-search incumbent is only one member of the pool passed forward. Linear scoring changes which partial prefixes are allowed to survive and therefore changes the distribution of the final completed pool. Even if the linear model is imperfect as a point predictor, it can act as a diversification mechanism: it may keep prefixes that GRA median scoring ranks lower but that lead to better local-search basins. On VC02, that basin difference cascades from BS to LS/ILS.")
        println(io)
        println(io, "The opposite can also happen. If linear keeps solutions that are diverse but hard to improve, the beam phase may be faster while RVND and ILS spend more time exploring difficult neighborhoods. That is exactly why stage-separated runtime and pool diversity measures are needed.")
        println(io)
        println(io, "## Next experiments")
        println(io)
        println(io, "- Pool cap after BS: run linear with LS applied to only top 100, 200, 500, and 1000 completed solutions. This directly tests whether the end-to-end slowdown comes from improving too many/harder candidates.")
        println(io, "- Shortlist multiplier: test 1, 2, 3, and 4. Smaller values should save beam time but may lose quality; larger values should approach GRA behavior.")
        println(io, "- Linear regularization and warmup: test `surrogate_min_samples` of 16, 32, 64, 128 and ridge `lambda` of 0.1, 1.0, 10.0.")
        println(io, "- Beam width interaction: test `w = 1, 2, 4`. If linear provides enough ranking information, smaller `w` may keep quality with less branching.")
        println(io, "- Greedy stochasticity interaction: test `q = 1, 2, 3`. If the learned model already smooths ranking noise, lower `q` may be enough.")
        println(io, "- Feature ablation: remove one feature group at a time: cost/count, inventory slack, time urgency, vessel utilization, port/vessel balance.")
        println(io)
        println(io, "## Generated tables")
        println(io)
        println(io, "- `results/linear_surrogate_stage_time_table.csv`")
        println(io, "- `results/linear_surrogate_objective_cascade_table.csv`")
    end
end

function main()
    gra_csv = parse_string_arg("gra", DEFAULT_GRA_CSV)
    linear_csv = parse_string_arg("linear", DEFAULT_LINEAR_CSV)
    out_dir = parse_string_arg("out-dir", "results")
    mkpath(out_dir)

    gra_rows = read_simple_csv(gra_csv)
    linear_rows = read_simple_csv(linear_csv)
    stage_rows = stage_comparison_rows(gra_rows, linear_rows)
    objective_rows = objective_comparison_rows(gra_rows, linear_rows)

    stage_csv = joinpath(out_dir, "linear_surrogate_stage_time_table.csv")
    objective_csv = joinpath(out_dir, "linear_surrogate_objective_cascade_table.csv")
    report_path = joinpath(out_dir, "linear_surrogate_analysis_plan_report.md")

    write_table_csv(stage_csv, stage_rows)
    write_table_csv(objective_csv, objective_rows)
    write_report(report_path, stage_rows, objective_rows, gra_csv, linear_csv)

    println("Wrote $(stage_csv)")
    println("Wrote $(objective_csv)")
    println("Wrote $(report_path)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
