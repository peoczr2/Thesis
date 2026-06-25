# Results Chapter Calculation Outline

This document is the blueprint for the experimental results chapter. The goal is not only to list tables, but to make clear what each table or figure proves.

The thesis has two layers:

1. Replication: reproduce the BS-LS-ILS structure from the paper using the original GRA-based beam scoring.
2. Extension: replace part of the expensive GRA scoring with an online linear surrogate and test whether this improves objective value, runtime, or both.

The central extension question is:

Can a linear model predict which partial MIRP solutions are promising well enough to reduce expensive greedy completions without losing solution quality?

## Common Raw Data Needed For Every Run

Every algorithm run should produce one row with at least these fields:

| Field | Meaning | Used for |
|---|---|---|
| `instance` | MIRPLib instance name | All grouping |
| `horizon` | Planning horizon, e.g. 120, 180, 360 | Horizon comparison |
| `seed` | Random seed | Best/average over seeds |
| `N` | Beam pool size | N sensitivity |
| `w` | Max children kept per node | Beam-width tuning |
| `q` | Number of GRA completions per successor | GRA stochasticity tuning |
| `scorer` | `gra` or `predictive` | Baseline vs extension |
| `surrogate_model` | Usually `linear` for the thesis extension | Extension identification |
| `surrogate_min_samples` | Samples before linear model is allowed to score | Takeover analysis |
| `surrogate_lambda` | Ridge regularization | Linear hyperparameter analysis |
| `surrogate_shortlist_multiplier` | Predictive shortlist size relative to `w` | Aggressiveness analysis |
| `objective` | Reference or best-known solution value | Gap calculation |
| `bs_cost` | Best solution after beam search | Construction quality |
| `ls_cost` | Best solution after local search | LS improvement |
| `ils_cost` | Best solution after ILS | Final quality |
| `bs_gap_pct` | Gap after BS | Stage boxplots |
| `ls_gap_pct` | Gap after LS | Stage boxplots |
| `ils_gap_pct` | Gap after ILS | Main comparison |
| `beam_seconds` | Time spent in beam search | Construction runtime |
| `ls_seconds` | Time spent in LS | Improvement workload |
| `ils_seconds` | Time spent in ILS | Improvement workload |
| `total_seconds` | Total measured runtime | Main runtime comparison |
| `beam_pool` | Number of complete candidate solutions passed to LS | Pool-size analysis |
| `ls_improvements` | Number of pool candidates improved by LS | Pool difficulty |
| `levels` | Beam levels completed | Search-depth comparison |

Gap formula:

```text
gap_pct = 100 * (cost - reference_cost) / reference_cost
```

Stage improvement formulas:

```text
bs_to_ls_gain = bs_cost - ls_cost
ls_to_ils_gain = ls_cost - ils_cost
bs_to_ils_gain = bs_cost - ils_cost
```

Runtime share formulas:

```text
beam_share_pct = 100 * beam_seconds / total_seconds
ls_share_pct = 100 * ls_seconds / total_seconds
ils_share_pct = 100 * ils_seconds / total_seconds
```

## Section 1: Replication Setup

### 1.1 ILS Parameters Taken From The Paper

Purpose: justify that the thesis does not retune ILS and keeps the improvement phase comparable with the paper.

What to report:

| Parameter | Value | Source | Reason |
|---|---:|---|---|
| Initial SA probability | Paper Table 4 value | Paper | Same acceptance behavior |
| Final SA probability | Paper Table 4 value | Paper | Same cooling behavior |
| ILS iterations | Paper Table 4 value | Paper | Same improvement budget |
| Restore-after threshold | Paper Table 4 value | Paper | Same restart behavior |
| Perturbations | Paper Table 4 value | Paper | Same perturbation strength |

What this shows:

The extension changes beam-node evaluation only. The LS/ILS improvement machinery is held constant.

### 1.2 Replication Metrics

Purpose: make the replication comparable to Tables 5-7 and Appendix C in the paper.

Calculate for each instance, horizon, N, and seed group:

| Metric | Calculation | Shows |
|---|---|---|
| Best final cost | `minimum(ils_cost)` over seeds | Best achieved quality |
| Average final cost | `mean(ils_cost)` over seeds | Expected quality |
| Best final gap | `minimum(ils_gap_pct)` over seeds | Best relative quality |
| Average final gap | `mean(ils_gap_pct)` over seeds | Robustness over seeds |
| Total runtime | `sum(total_seconds)` or mean runtime per seed | Computational effort |
| Stage costs | mean or best of `bs_cost`, `ls_cost`, `ils_cost` | How each stage contributes |
| Stage times | mean of `beam_seconds`, `ls_seconds`, `ils_seconds` | Where time is spent |

## Section 2: Parameter Tuning For The Replication

### 2.1 Beam Width `w`

Purpose: show whether the paper-style beam width remains sensible in this implementation, and whether linear scoring changes the best `w`.

Run:

- Instances: `LR1_DR02_VC01_V6a` and `LR1_DR02_VC02_V6a`
- Fixed `N = 250`
- Compare both `scorer=gra` and `scorer=predictive --surrogate-model=linear`
- Suggested `w`: 1, 2, 3, 4, 5, 6, 7
- Same seed set for both scorers

Table:

| Scorer | Instance | `w` | Avg BS gap | Avg ILS gap | Avg beam time | Avg total time |
|---|---|---:|---:|---:|---:|---:|
| GRA | VC01 | 1 |  |  |  |  |
| Linear | VC01 | 1 |  |  |  |  |

Figure:

- Line plot with `w` on x-axis.
- Left y-axis or separate panel: average objective gap.
- Right y-axis or separate panel: average runtime.
- Separate lines for GRA and linear.

What this shows:

If linear scoring is useful, it may need a different `w` than GRA. A smaller `w` with linear can show that the learned ranking provides enough guidance to prune more aggressively.

### 2.2 GRA Randomness `q`

Purpose: test whether stochastic GRA completions are still needed when linear scoring is used.

Run:

- Instances: `LR1_DR02_VC01_V6a` and `LR1_DR02_VC02_V6a`
- Fixed `N = 250`, selected `w`
- Compare `q = 1, 2, 3, 5`
- Compare GRA and linear

Table:

| Scorer | Instance | `q` | Avg BS gap | Avg ILS gap | Avg beam time | Avg total time | GRA calls |
|---|---|---:|---:|---:|---:|---:|---:|
| GRA | VC01 | 1 |  |  |  |  |  |
| Linear | VC01 | 1 |  |  |  |  |  |

What this shows:

The original method uses repeated GRA completions to reduce noisy partial-solution evaluation. If the linear model already smooths the ranking, smaller `q` may preserve quality while reducing time.

### 2.3 GRA Randomness Design

Purpose: replicate the paper's argument that randomizing some GRA choices is beneficial.

Run:

- Use the 13 smallest 120-period instances if feasible.
- Fixed `q = 5`, `N = 1000`
- Compare no randomization, random port, random vessel, both random.

Table:

| Instance | No random avg cost | Random port avg cost | Random vessel avg cost | Both random avg cost |
|---|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a |  |  |  |  |
| Average |  |  |  |  |

What this shows:

This supports the choice of GRA teacher behavior used to train the linear model.

## Section 3: Main Replication Benchmark

### 3.1 Main Results By `N`

Purpose: reproduce the paper-style quality/runtime trade-off for the baseline algorithm.

Run:

- `N = 10, 100, 1000`
- Horizons: 120, 180, 360
- 10 seeds per instance if computationally feasible
- Time cap: 14400 seconds for long horizon comparisons, or state clearly if a different cap is used

Table:

| Horizon | `N` | Instance | Class | Best cost | Best gap | Avg cost | Avg gap | Avg total time |
|---|---:|---|---|---:|---:|---:|---:|---:|
| 120 | 10 | LR1_DR02_VC01_V6a | E |  |  |  |  |  |

What this shows:

Increasing `N` should generally improve quality but increase runtime. This establishes the bottleneck that motivates the linear surrogate.

### 3.2 Stage-By-Stage Breakdown

Purpose: show how much BS, LS, and ILS each contribute to solution quality and runtime.

Table:

| Horizon | `N` | Instance | BS gap | BS time | LS gap | LS time | ILS gap | ILS time |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| 120 | 10 | LR1_DR02_VC01_V6a |  |  |  |  |  |  |

Figures:

- Boxplot of gap by stage: x-axis `N`, hue/stage `BS`, `LS`, `ILS`, y-axis gap percentage.
- Create this for horizon 120.
- Repeat for horizons 180 and 360.
- Cap or annotate runs exceeding 14400 seconds.

What this shows:

If most improvement happens after BS, the final result depends strongly on the candidate pool passed to LS/ILS. This is important for interpreting why linear can improve final cost even when its beam prediction is imperfect.

## Section 4: Baseline GRA vs Linear Extension

### 4.1 Direct Final Comparison

Purpose: answer the main extension question: does linear improve objective, runtime, or both?

Run:

- Same instances, horizons, `N`, `w`, `q`, seeds for both methods.
- Baseline: `scorer=gra`
- Extension: `scorer=predictive --surrogate-model=linear`

Table:

| Horizon | `N` | Instance | Class | GRA avg gap | Linear avg gap | Gap delta | GRA avg time | Linear avg time | Time reduction |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|
| 120 | 1000 | LR1_DR02_VC01_V6a | E |  |  |  |  |  |  |

Calculations:

```text
gap_delta = linear_avg_gap - gra_avg_gap
time_reduction_pct = 100 * (gra_avg_time - linear_avg_time) / gra_avg_time
```

Interpretation:

- Negative `gap_delta`: linear finds better solutions.
- Positive `time_reduction_pct`: linear is faster.
- If linear has better gap but worse time, describe it as a diversification/quality mechanism, not yet an acceleration win.
- If linear has same gap and lower beam time, describe it as a successful construction-phase acceleration.

### 4.2 Best Gap Comparison By Horizon

Purpose: show whether linear helps more on short or long planning horizons.

Figure:

- Boxplot of best gap.
- x-axis: horizon.
- hue: GRA vs linear.
- optionally facet by `N`.

Calculation:

For each instance/horizon/scorer/N:

```text
best_gap = minimum(ils_gap_pct over seeds)
```

What this shows:

Whether the learned scorer remains useful as the horizon grows and the search tree becomes harder.

### 4.3 Average Objective Or Average Gap Comparison

Purpose: show robustness, not just lucky best-seed performance.

Figure:

- Boxplot of average gap or average objective value.
- x-axis: horizon or `N`.
- hue: GRA vs linear.

Calculation:

```text
avg_gap = mean(ils_gap_pct over seeds)
avg_obj = mean(ils_cost over seeds)
```

What this shows:

If linear is consistently good, average performance should improve or remain close to GRA. If only best gap improves, linear may be more volatile.

### 4.4 Runtime Comparison

Purpose: separate total runtime from beam-search runtime.

Figures:

- Boxplot of total execution time by horizon, hue GRA vs linear.
- Boxplot of beam time by horizon, hue GRA vs linear.
- Stacked bar or grouped bar of beam, LS, and ILS time shares.

Calculations:

```text
avg_beam_time = mean(beam_seconds)
avg_ls_time = mean(ls_seconds)
avg_ils_time = mean(ils_seconds)
avg_total_time = mean(total_seconds)
beam_time_reduction_pct = 100 * (gra_beam_time - linear_beam_time) / gra_beam_time
total_time_reduction_pct = 100 * (gra_total_time - linear_total_time) / gra_total_time
```

What this shows:

The current early results suggest linear can reduce beam time while increasing LS/ILS time. This distinction is essential; otherwise the conclusion becomes misleading.

### 4.5 Gap And Time By Instance Class

Purpose: test whether the extension helps easy, medium, or hard instances differently.

Figure:

- Boxplot of final gap by `N`, hue GRA vs linear, facet by class E/M/H.
- Boxplot of execution time by `N`, hue GRA vs linear, facet by class E/M/H.

What this shows:

The surrogate should be most valuable where GRA scoring is expensive. If hard instances benefit more, this strengthens the thesis contribution.

## Section 5: Explaining Why Linear Can Improve Objective

### 5.1 Objective Cascade Table

Purpose: show whether the improvement appears in BS, LS, or ILS.

Table:

| Instance | GRA BS | Linear BS | BS delta | GRA LS | Linear LS | LS delta | GRA ILS | Linear ILS | ILS delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC02_V6a |  |  |  |  |  |  |  |  |  |

Calculations:

```text
bs_delta = linear_bs_cost - gra_bs_cost
ls_delta = linear_ls_cost - gra_ls_cost
ils_delta = linear_ils_cost - gra_ils_cost
```

What this shows:

- If `bs_delta < 0`, linear already found a better construction solution.
- If `bs_delta >= 0` but `ils_delta < 0`, linear changed the candidate pool in a way that helped LS/ILS find a better basin.
- If BS is equal and beam time is lower, linear accelerated construction without quality loss at BS.

### 5.2 Same-BS-Cost Cases

Purpose: isolate runtime effects from objective effects.

Table:

| Instance | Same BS cost | GRA beam time | Linear beam time | Beam time reduction | GRA total time | Linear total time |
|---|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a |  |  |  |  |  |  |

What this shows:

When `bs_cost` is identical, quality is controlled. Any difference in beam time shows pure construction-phase efficiency, while any difference in LS/ILS time shows that the saved pool still matters.

### 5.3 Candidate Pool Diversity

Purpose: test the hypothesis that linear can produce a more useful or more diverse final pool.

Use the diagnostic runner and calculate:

| Metric | Calculation | Interpretation |
|---|---|---|
| Pool cost spread | `p90_cost - p10_cost` | Wider objective distribution means broader search |
| Pool cost std | `std(pool_costs)` | Overall objective diversity |
| Unique route signatures | Count unique sequences of `(port, vessel)` | Structural diversity |
| Unique signatures in top 100 | Same count for best 100 pool candidates | Diversity among promising candidates |
| Avg pairwise route distance top 100 | Average normalized Hamming distance between call sequences | Route-shape diversity |
| Call-count spread | `max_calls - min_calls` | Different route lengths |

Table:

| Instance | Scorer | Pool cost std | Unique top100 | Avg route distance top100 | Best pool cost | Median pool cost |
|---|---|---:|---:|---:|---:|---:|
| VC02 | GRA |  |  |  |  |  |
| VC02 | Linear |  |  |  |  |  |

What this shows:

If linear improves final objective while not clearly improving BS incumbent, diversity is the likely explanation. LS/ILS may be receiving candidates from a different basin.

## Section 6: Proving The Linear Model Learns Something

### 6.1 Surrogate Activity And Takeover

Purpose: show when the algorithm switches from GRA scoring to linear predictions.

Use level diagnostics:

| Field | Meaning |
|---|---|
| `level` | Beam depth |
| `training_samples` | Number of GRA-labelled examples collected |
| `model_trained` | Whether linear model is active |
| `use_gra_scoring` | Whether this level still uses GRA for all successors |
| `predicted_successors` | Successors scored by linear prediction |
| `gra_scored_successors` | Successors completed by GRA |
| `completed_solutions` | Full GRA completions generated |

Derived calculations:

```text
prediction_share = predicted_successors / feasible_successors
gra_scoring_share = gra_scored_successors / feasible_successors
gra_completion_saving = 1 - (linear_gra_scored_successors / gra_gra_scored_successors)
```

Table:

| Instance | Level | Training samples | Model active | Prediction share | GRA scored successors | Completed solutions |
|---|---:|---:|---|---:|---:|---:|
| VC01 | 1 |  |  |  |  |  |

What this shows:

Linear is not just another label; it actually takes over part of the expensive scoring process.

### 6.2 Prediction Accuracy

Purpose: prove that the linear model predicts GRA-completed quality with useful accuracy.

Additional raw data needed:

For every shortlisted successor that is predicted and then GRA-completed, store:

| Field | Meaning |
|---|---|
| `predicted_score` | Linear prediction before GRA completion |
| `actual_gra_score` | GRA median score after completion |
| `level` | Beam level |
| `rank_predicted` | Rank before GRA |
| `rank_actual` | Rank after GRA |

Calculations:

```text
error = predicted_score - actual_gra_score
absolute_error = abs(error)
squared_error = error^2
MAE = mean(absolute_error)
RMSE = sqrt(mean(squared_error))
rank_error = abs(rank_predicted - rank_actual)
```

Table:

| Instance | Early MAE | Late MAE | Early RMSE | Late RMSE | Avg rank error | Spearman rank correlation |
|---|---:|---:|---:|---:|---:|---:|
| VC01 |  |  |  |  |  |  |

Early/late split:

```text
early = first 10% of predicted-and-verified nodes
late = last 10% of predicted-and-verified nodes
```

What this shows:

If late MAE/RMSE is lower than early MAE/RMSE, the online model improves as it receives more GRA labels. If rank correlation is high, it is useful for beam search even when exact score prediction is imperfect.

### 6.3 Feature Analysis

Purpose: explain what the linear model uses to rank partial solutions.

Current feature groups:

| Feature group | Features | Expected meaning |
|---|---|---|
| Cost/progress | `prefix_cost`, `call_count`, `remaining_horizon` | How expensive and deep the partial route is |
| Inventory risk | `next_violation_urgency`, `min_inventory_slack`, `mean_inventory_slack` | Whether ports are close to violation |
| Vessel state | `vessel_utilization`, `vessel_time_spread` | Whether vessels are balanced and usable |
| Port balance | `port_imbalance` | Loading/unloading inventory balance |
| Future flexibility | `feasible_arc_ratio` | How many feasible moves remain |
| Route coverage | `unique_port_ratio`, `unique_vessel_ratio` | How broadly ports/vessels are used |

Calculations:

- Standardized linear coefficients by feature.
- Absolute coefficient ranking.
- Feature ablation runs by removing one feature group at a time.

Table:

| Feature | Standardized coefficient | Absolute rank | Interpretation |
|---|---:|---:|---|
| prefix_cost |  |  |  |

What this shows:

This makes the ML part interpretable and connects prediction behavior to MIRP structure.

## Section 7: Linear Hyperparameter And Aggressiveness Analysis

### 7.1 Takeover Aggressiveness

Purpose: find whether linear should take over early or conservatively.

Use:

- `surrogate_min_samples`: 16, 32, 64, 128
- `surrogate_shortlist_multiplier`: 1, 2, 3, 4

Table:

| Min samples | Shortlist multiplier | Avg gap | Avg beam time | Avg total time | GRA calls | LR predictions |
|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1 |  |  |  |  |  |

What this shows:

Lower min samples and smaller shortlist are more aggressive. They should reduce beam time but may lose quality if the model is not ready.

### 7.2 Ridge Regularization

Purpose: test whether the linear model overfits noisy online GRA labels.

Use:

- `surrogate_lambda`: 0.01, 0.1, 1.0, 10.0, 100.0

Table:

| Lambda | Avg prediction MAE | Avg ILS gap | Avg beam time | Avg total time |
|---:|---:|---:|---:|---:|
| 0.01 |  |  |  |  |

What this shows:

If larger lambda improves final results, the model was overfitting. If smaller lambda improves results, stronger feature response is useful.

## Section 8: Recommended Final Thesis Figures

### Replication Figures

| Figure | Data source | Shows |
|---|---|---|
| Boxplot BS/LS/ILS gap by `N`, horizon 120 | Stage table | Improvement from each heuristic stage |
| Boxplot BS/LS/ILS gap by `N`, horizons 180 and 360 | Stage table | Scaling with horizon |
| Boxplot runtime by `N` and horizon | Main benchmark table | Cost of larger beam size |
| Best/avg gap by horizon | Main benchmark table | Replication quality vs paper-style reference |

### Extension Figures

| Figure | Data source | Shows |
|---|---|---|
| Best gap by horizon: GRA vs linear | Main GRA/linear comparison | Quality impact |
| Average objective/gap: GRA vs linear | Main GRA/linear comparison | Robustness |
| Total time: GRA vs linear | Main GRA/linear comparison | End-to-end runtime |
| Beam time only: GRA vs linear | Stage-time table | Whether scoring is accelerated |
| Stage time stacked bars | Stage-time table | Whether LS/ILS consume saved time |
| Gap by `N` and class E/M/H | Main GRA/linear comparison | Where linear helps most |
| Runtime by `N` and class E/M/H | Main GRA/linear comparison | Scaling by difficulty |
| Prediction share by beam level | Level diagnostics | Linear takeover behavior |
| GRA calls vs LR predictions by level | Level diagnostics | Direct saving of greedy completions |
| Pool diversity comparison | Pool diagnostics | Why final objective can improve |
| Prediction MAE/RMSE over levels | Prediction diagnostic table | Whether LR learns online |

## Section 9: Minimal Evidence Needed For A Strong Extension Claim

To claim the linear extension is successful, at least one of these should be demonstrated:

1. Same or better final gap with lower total runtime.
2. Same or better BS cost with lower beam-search time.
3. Better final ILS cost caused by a different and more diverse candidate pool.
4. Useful prediction behavior: high ranking correlation or decreasing MAE/RMSE over the search.
5. Better scaling: linear allows larger `N` under the same time budget.

The current early result already supports item 2 on some instances and item 3 on VC02. The missing evidence is prediction accuracy and pool-diversity diagnostics at the same experimental scale.

## Section 10: Existing Scripts And Outputs

Current analysis scripts:

| Script | Purpose |
|---|---|
| `analyze_linear_surrogate_results.jl` | Creates stage-time and objective-cascade tables from completed GRA and linear replication CSVs |
| `linear_surrogate_diagnostic_runner.jl` | Runs beam-only diagnostics for takeover, GRA call savings, and pool diversity |
| `replication_runner_parallel.jl` | Runs full BS-LS-ILS batches in parallel |

Current generated outputs:

| Output | Purpose |
|---|---|
| `results/linear_surrogate_analysis_plan_report.md` | Current GRA-vs-linear interpretation |
| `results/linear_surrogate_stage_time_table.csv` | Stage-time comparison |
| `results/linear_surrogate_objective_cascade_table.csv` | BS/LS/ILS objective cascade |
| `results/linear_surrogate_level_diagnostics_*.csv` | Per-level linear takeover diagnostics |
| `results/linear_surrogate_pool_diagnostics_*.csv` | Final beam-pool diversity diagnostics |
