# Replication Progress Update After GRA Changes

## Run Status

I reran the paper-parameter configuration after the latest Beam Search / GRA changes:

- Horizon: `120`
- Seed: `1`
- Beam nodes per level: `N = 1000`
- Children per node: `w = 2`
- Greedy completions per successor: `q = 3`
- ILS parameters: Table 4 defaults in `PAPER_ILS_PARAMETERS`

The full six-instance batch did not finish before the two-hour command timeout. I then continued individual runs and completed one more instance. The interrupted `LR1_DR02_VC04_V8a` run was stopped before completion, and `LR1_DR02_VC05_V8a` was not rerun after the latest changes.

Completed after the latest changes:

| Instance | Paper objective | Paper best | New ILS | Gap vs objective | Diff vs paper best |
|---|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33,809.00 | 33,808.95 | 33,440.17 | -1.09% | -368.78 |
| LR1_DR02_VC02_V6a | 74,982.00 | 74,981.65 | 77,626.47 | 3.53% | 2,644.82 |
| LR1_DR02_VC03_V7a | 40,446.00 | 40,340.01 | 43,294.63 | 7.04% | 2,954.62 |
| LR1_DR02_VC03_V8a | 43,721.00 | 43,721.43 | 44,027.39 | 0.70% | 305.96 |

Not completed after the latest changes:

| Instance | Status |
|---|---|
| LR1_DR02_VC04_V8a | Started individually, then interrupted and stopped. |
| LR1_DR02_VC05_V8a | Not rerun after the latest GRA/cache changes. |

The partial CSV from the batch is:

`results/bs_ils_replication_paper_after_gra_changes_120_20260612_110314.csv`

## What Changed Before This Rerun

The main algorithmic changes before this rerun were:

- Beam/GRA appends now use `append_evaluated_call`, which evaluates only the newly appended call instead of rebuilding the whole sequence from period 0.
- `Solution` now caches `port_next_violation`, so GRA reads the next violation period directly instead of recalculating it during every port-selection step.
- `is_feasible` now follows the paper's route-compatibility rule: vessels alternate between loading and unloading ports, while cargo is derived from the route.
- `greedy_complete_solution` no longer stops the whole completion when one extension fails. It skips the unschedulable port for the current prefix and tries another urgent port.
- The deterministic and stochastic GRA logic is now mostly inline in `greedy_complete_solution`, which makes the construction easier to audit.

## Comparison With The Paper

The latest completed results are mixed.

`LR1_DR02_VC01_V6a` is still better than the paper's reported value. That is not enough to claim a true improvement, because it may indicate remaining cost-model differences.

`LR1_DR02_VC02_V6a` remains materially above the paper by about `2,644.82`, or `3.53%` against the objective baseline. This suggests either the construction is still missing a detail from the authors' GRA/BS pruning, or the local search/ILS is not exploring the same neighborhood sequence.

`LR1_DR02_VC03_V7a` became slightly worse than the previous full run after the latest GRA changes: `43,294.63` now versus `43,095.86` before. That does not necessarily mean the logic is worse overall, because the change corrected the construction semantics and also changed the generated search tree. But it does mean this instance is still not close to the paper.

`LR1_DR02_VC03_V8a` is now close to the paper: `0.70%` above objective and about `305.96` above the paper best. This is a reasonable replication-level result, though not exact.

## Honest Assessment

The replication is structurally much closer to the paper than the original version: BS uses GRA to score partial nodes, GRA prioritizes inventory-risk ports, failed extensions are discarded without losing the prefix, and append evaluation is now incremental. The remaining results are plausible rather than obviously broken.

However, this is still not an exact replication. The two largest completed gaps, especially `LR1_DR02_VC03_V7a`, are too large to explain as rounding or random noise. There is still uncertainty in several places where the paper does not fully specify implementation details:

- Exact stochastic sampling distribution and tie-breaking in GRA.
- Whether the authors randomize vessel choice in the final configuration or only port choice.
- Exact duplicate-state logic in beam selection.
- Whether local search is applied to every completed beam solution, only selected BS outputs, or only the final incumbent.
- Exact ILS simulated annealing schedule from the reported initial/final probabilities.
- Some cost-accounting details, especially timing of inventory correction, source/sink arcs, and end-of-horizon treatment.

The safest conclusion is that the implementation is now a credible approximate replication of the paper's Beam Search + GRA + ILS framework, but not a confirmed code-level reproduction of the authors' heuristic. The remaining discrepancies should be described as unresolved implementation uncertainty rather than hidden hyperparameter issues.
