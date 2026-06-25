# ML Surrogate Beam Scoring Comparison

Generated: 2026-06-23

## Experiment Setup

- Horizon: `120`
- Instances: six `LR1_DR02_*` instances used by the replication runner
- Seed: `1`
- Beam search: `N = 1000`, `w = 2`
- Greedy completions: `q = 3`
- ILS iterations: `640`
- Parallel workers: `6`
- Baseline CSV: `results/bs_ils_replication_mlcmp_gra_120_20260623_091648.csv`
- Predictive-linear CSV: `results/bs_ils_replication_mlcmp_linear_120_20260623_093113.csv`

Tree and forest CSVs were not present in `results/` when this report was generated, so this report compares the completed GRA and predictive-linear batches. Add the tree/forest runs later to complete the full method table.

## Main Comparison

Lower objective and lower runtime are better. `Obj delta` is predictive-linear minus GRA, so negative means the predictive-linear method improved the final ILS objective.

| Instance | GRA ILS | Linear ILS | Obj delta | GRA gap | Linear gap | Beam delta | Total delta | Note |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| LR1_DR02_VC01_V6a | 33808.95 | 33808.95 | 0.00 | 0.00% | 0.00% | -22.08% | 83.49% | same objective |
| LR1_DR02_VC02_V6a | 78052.08 | 77928.08 | -124.00 | 4.09% | 3.93% | -2.73% | 116.35% | better objective |
| LR1_DR02_VC03_V7a | 40589.73 | 40593.57 | 3.84 | 0.36% | 0.36% | -7.59% | 113.59% | slightly worse |
| LR1_DR02_VC03_V8a | 43772.61 | 43772.61 | 0.00 | 0.12% | 0.12% | -30.50% | 76.39% | same objective |
| LR1_DR02_VC04_V8a | 41708.66 | 41708.68 | 0.02 | 0.12% | 0.12% | 2.79% | 185.43% | essentially tied |
| LR1_DR02_VC05_V8a | 36603.23 | 36603.23 | 0.00 | -0.15% | -0.15% | -10.33% | 137.57% | same objective |

## Phase Runtime Breakdown

| Instance | GRA beam | Linear beam | GRA LS | Linear LS | GRA ILS | Linear ILS |
|---|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 166.83 | 129.99 | 138.43 | 324.01 | 194.36 | 462.76 |
| LR1_DR02_VC02_V6a | 248.84 | 242.05 | 181.56 | 476.37 | 186.66 | 616.61 |
| LR1_DR02_VC03_V7a | 287.98 | 266.12 | 190.41 | 500.15 | 174.37 | 627.97 |
| LR1_DR02_VC03_V8a | 214.95 | 149.39 | 128.77 | 325.93 | 157.26 | 408.39 |
| LR1_DR02_VC04_V8a | 501.58 | 515.59 | 176.86 | 775.90 | 150.60 | 1074.80 |
| LR1_DR02_VC05_V8a | 421.39 | 377.84 | 176.33 | 557.07 | 147.47 | 835.42 |

## Aggregate Results

| Metric | Predictive-linear vs GRA |
|---|---:|
| Average beam-time change | -11.74% |
| Instances with faster beam phase | 5 / 6 |
| Average total-time change | +118.80% |
| Instances with faster total runtime | 0 / 6 |
| Sum measured runtime, GRA | 3844.63 s |
| Sum measured runtime, predictive-linear | 8666.33 s |
| Parallel batch wall time, GRA | 837.71 s |
| Parallel batch wall time, predictive-linear | 2375.64 s |
| Average final-objective change | -20.02 |
| Average final-gap change | -0.03 percentage points |

## Interpretation

The predictive-linear surrogate succeeds at the narrow beam-search goal: it reduces beam time on five of the six instances, with an average beam-time reduction of about `11.74%`. This means the learned scorer is doing useful work as a cheaper filter for successor nodes.

However, the full BS-LS-ILS pipeline is slower with predictive-linear. The reason is not the beam phase; it is the downstream improvement phase. Local search and ILS become much more expensive for the predictive-linear solution pool. The final pool size remains `1000`, but the pool appears to contain solutions that are costlier for RVND/ILS to improve. This turns a beam-time win into a total-runtime loss.

The most interesting objective result is `LR1_DR02_VC02_V6a`: predictive-linear improves the final objective by `124.00`, reducing the gap from `4.09%` to `3.93%`. This is the instance where the original replication was weakest, so the surrogate may be introducing useful diversification. On the other instances, the final objective is either identical or only negligibly different.

## Thesis Takeaway

The ML surrogate should not be presented as a full replacement that is already faster end-to-end. The stronger claim is:

> A learned surrogate can reduce the cost of beam-node evaluation and sometimes guide the search into better basins, but the downstream local-search workload must be controlled for the runtime benefit to survive the full BS-LS-ILS pipeline.

This is still a useful thesis result because it identifies a non-obvious interaction: optimizing the construction phase alone can make the improvement phase harder.

## Recommended Next Experiments

1. Cap the local-search pool for predictive methods, for example improve only the best `100`, `200`, or `500` completed beam candidates instead of all `1000`.
2. Try predictive-linear with `surrogate_shortlist_multiplier = 1` and `3` to test the exploration/runtime tradeoff.
3. Run tree and forest batches with the same paper settings so they can be added to this table.
4. For forest, start with `--surrogate-forest-trees=4` before trying `8` or `12`; the forest model is likely to be dominated by fitting overhead.
5. Track not only final cost and runtime, but also average calls per saved beam-pool solution and local-search time per candidate. That would directly test whether the predictive pool is harder to improve.
