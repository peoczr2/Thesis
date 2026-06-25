# Linear surrogate analysis plan and current evidence

Generated: 2026-06-23 13:35

Input GRA CSV: `results/bs_ils_replication_mlcmp_gra_120_20260623_091648.csv`
Input linear CSV: `results/bs_ils_replication_mlcmp_linear_120_20260623_093113.csv`

## What should be measured

The linear scorer should not be judged only by final ILS cost or only by total runtime. It changes the construction phase and also changes the pool of completed solutions that LS and ILS receive. The useful measurements are therefore:

- Construction quality: `bs_cost`, beam levels, and whether the same or better BS incumbent is found.
- Construction runtime: `beam_seconds` and the beam share of total runtime.
- Improvement workload: `ls_seconds`, `ils_seconds`, `ls_improvements`, and local-search gain from BS to LS.
- Final quality cascade: whether a different BS pool gives LS/ILS a better basin, even when the immediate BS incumbent is not better.
- Pool diversity: final-pool objective spread, unique route signatures, call-count spread, and pairwise route distance from diagnostic runs.
- Prediction behavior: per-level training samples, when the model becomes active, how many successors are predicted versus GRA-completed, and prediction error on the shortlisted nodes.

## Current headline

Across the current six horizon-120 runs, linear made the beam phase faster on 5/6 instances, with an average beam-time change of -11.74%. However, total measured runtime increased by 118.80% on average because LS and ILS became much more expensive. Final ILS cost improved on 1/6 instances, and 2/6 instances had the same BS incumbent under GRA and linear.

The thesis point is stronger if phrased as: the linear model is a learned construction-phase filter that can preserve or improve construction quality while reducing GRA completions, but its downstream value depends on controlling the size and difficulty of the LS/ILS pool.

## Stage-time comparison

| Instance | BS change | LS change | ILS change | Total change | Linear extra LS+ILS (s) | Linear beam share |
|---|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | -22.08% | 134.06% | 138.10% | 83.49% | 453.98 | 14.18% |
| LR1_DR02_VC02_V6a | -2.73% | 162.38% | 230.33% | 116.35% | 724.76 | 18.13% |
| LR1_DR02_VC03_V7a | -7.59% | 162.66% | 260.14% | 113.59% | 763.33 | 19.09% |
| LR1_DR02_VC03_V8a | -30.50% | 153.10% | 159.69% | 76.39% | 448.29 | 16.91% |
| LR1_DR02_VC04_V8a | 2.79% | 338.71% | 613.68% | 185.43% | 1523.24 | 21.79% |
| LR1_DR02_VC05_V8a | -10.33% | 215.93% | 466.50% | 137.57% | 1068.69 | 21.34% |

Sum measured time: GRA 3844.63 s, linear 8666.33 s.

## Objective cascade

| Instance | GRA BS | Linear BS | BS delta | GRA ILS | Linear ILS | ILS delta | Gap delta | Linear LS gain |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33808.97 | 33808.97 | 0.00 | 33808.95 | 33808.95 | -0.00 | -0.000 pp | 0.02 |
| LR1_DR02_VC02_V6a | 78052.08 | 77928.08 | -124.00 | 78052.08 | 77928.08 | -124.00 | -0.165 pp | 0.00 |
| LR1_DR02_VC03_V7a | 40992.20 | 40954.04 | -38.16 | 40589.73 | 40593.57 | 3.84 | 0.009 pp | 360.47 |
| LR1_DR02_VC03_V8a | 43772.61 | 43772.61 | 0.00 | 43772.61 | 43772.61 | 0.00 | 0.000 pp | 0.00 |
| LR1_DR02_VC04_V8a | 41948.52 | 41950.06 | 1.54 | 41708.66 | 41708.68 | 0.02 | 0.000 pp | 241.37 |
| LR1_DR02_VC05_V8a | 36623.99 | 36627.23 | 3.24 | 36603.23 | 36603.23 | 0.00 | 0.000 pp | 24.00 |

The VC02 result is the key positive quality example: linear improves the final ILS objective by -124.00 despite not changing the algorithm after construction. This means the learned scorer can redirect the search toward a different basin, and LS/ILS can inherit that advantage.

## Same beam incumbent cases

| Instance | Same BS cost | Beam time change | Total time change | Interpretation |
|---|---:|---:|---:|---|
| LR1_DR02_VC01_V6a | 33808.97 | -22.08% | 83.49% | same construction quality with faster beam phase |
| LR1_DR02_VC03_V8a | 43772.61 | -30.50% | 76.39% | same construction quality with faster beam phase |

These cases are useful for the thesis because they isolate the acceleration claim. If the BS incumbent is the same, then objective quality is held constant at construction time; any runtime difference shows whether the predictive scorer reduces construction work and whether downstream improvement dominates the total runtime.

## Why can the objective improve?

The beam-search incumbent is only one member of the pool passed forward. Linear scoring changes which partial prefixes are allowed to survive and therefore changes the distribution of the final completed pool. Even if the linear model is imperfect as a point predictor, it can act as a diversification mechanism: it may keep prefixes that GRA median scoring ranks lower but that lead to better local-search basins. On VC02, that basin difference cascades from BS to LS/ILS.

The opposite can also happen. If linear keeps solutions that are diverse but hard to improve, the beam phase may be faster while RVND and ILS spend more time exploring difficult neighborhoods. That is exactly why stage-separated runtime and pool diagnostics are needed.

## Next experiments

- Pool cap after BS: run linear with LS applied to only top 100, 200, 500, and 1000 completed solutions. This directly tests whether the end-to-end slowdown comes from improving too many/harder candidates.
- Shortlist multiplier: test 1, 2, 3, and 4. Smaller values should save beam time but may lose quality; larger values should approach GRA behavior.
- Linear regularization and warmup: test `surrogate_min_samples` of 16, 32, 64, 128 and ridge `lambda` of 0.1, 1.0, 10.0.
- Beam width interaction: test `w = 1, 2, 4`. If linear provides enough ranking information, smaller `w` may keep quality with less branching.
- Greedy stochasticity interaction: test `q = 1, 2, 3`. If the learned model already smooths ranking noise, lower `q` may be enough.
- Feature ablation: remove one feature group at a time: cost/count, inventory slack, time urgency, vessel utilization, port/vessel balance.

## Generated tables

- `results/linear_surrogate_stage_time_table.csv`
- `results/linear_surrogate_objective_cascade_table.csv`
