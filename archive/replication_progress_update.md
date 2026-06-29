# Replication Progress Update

## Summary

The replication is now much closer to the paper than in the first full run. After aligning the run with the paper-style parameters for the 120-period instances (`N = 1000`, `w = 2`, `q = 3`, and 640 ILS iterations), the average replicated ILS gap is **1.02%** against the paper's objective baseline. This is a substantial improvement over the earlier run, where several instances had large deviations caused by implementation issues in the construction/evaluation logic.

The current results are encouraging, but they should not yet be interpreted as a perfect reproduction of the authors' implementation. Some differences remain, especially for `LR1_DR02_VC02_V6a` and `LR1_DR02_VC03_V7a`, and there is still uncertainty about parts of the paper's heuristic that are not fully specified.

## Paper-Parameter Replication Results

The table below compares the current replicated results with the paper's reported best costs for the six 120-period instances.

| Instance | Objective | Paper best | Replicated BS | Replicated LS | Replicated ILS | ILS gap vs objective | Difference vs paper best |
|---|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33,809.00 | 33,808.95 | 33,440.17 | 33,440.17 | 33,440.17 | -1.09% | -368.78 |
| LR1_DR02_VC02_V6a | 74,982.00 | 74,981.65 | 77,626.47 | 77,626.47 | 77,626.47 | 3.53% | 2,644.82 |
| LR1_DR02_VC03_V7a | 40,446.00 | 40,340.01 | 43,095.86 | 43,095.86 | 43,095.86 | 6.55% | 2,755.85 |
| LR1_DR02_VC03_V8a | 43,721.00 | 43,721.43 | 43,332.15 | 43,332.15 | 43,332.15 | -0.89% | -389.28 |
| LR1_DR02_VC04_V8a | 41,657.00 | 41,708.65 | 41,304.29 | 41,304.29 | 41,062.98 | -1.43% | -645.67 |
| LR1_DR02_VC05_V8a | 36,659.00 | 36,536.62 | 36,465.26 | 36,465.26 | 36,465.26 | -0.53% | -71.36 |
| **Average** | **45,212.33** | **45,183.89** | **45,877.38** | **45,877.38** | **45,837.82** | **1.02%** | **653.93** |

## Progress Compared With Earlier Run

The first full replication run still had large gaps on several instances. After the later changes to the greedy randomized construction and evaluation logic, the results became much more stable and much closer to the paper.

| Instance | Earlier replicated ILS | Current replicated ILS | Earlier gap | Current gap | Change in gap |
|---|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 33,440.17 | 33,440.17 | -1.09% | -1.09% | 0.00 pp |
| LR1_DR02_VC02_V6a | 88,411.03 | 77,626.47 | 17.91% | 3.53% | -14.38 pp |
| LR1_DR02_VC03_V7a | 47,354.23 | 43,095.86 | 17.08% | 6.55% | -10.53 pp |
| LR1_DR02_VC03_V8a | 327,658.42 | 43,332.15 | 649.43% | -0.89% | -650.32 pp |
| LR1_DR02_VC04_V8a | 43,104.29 | 41,062.98 | 3.47% | -1.43% | -4.90 pp |
| LR1_DR02_VC05_V8a | 41,178.13 | 36,465.26 | 12.33% | -0.53% | -12.86 pp |

This shows that the replication has moved from a rough structural implementation toward a much more credible reproduction of the paper's BS-GRA-ILS behavior. The largest correction is on `LR1_DR02_VC03_V8a`, where the earlier result was clearly inconsistent with the paper, while the current result is close to the reported value.

## Interpretation

Four of the six instances are now close to, or below, the paper's reported best values. This suggests that the broad structure of the implementation is working: beam search constructs reasonable solutions, the greedy randomized completion is producing competitive schedules, and the local search / ILS phase is no longer causing obvious degradation.

However, the two positive gaps remain important. The current solution for `LR1_DR02_VC02_V6a` is about **2,644.82** above the paper's best, and `LR1_DR02_VC03_V7a` is about **2,755.85** above the paper's best. These are not small rounding differences. They indicate that either the search is still missing some neighborhoods or pruning behavior used by the authors, or that some implementation detail in the greedy completion, evaluation, or acceptance logic still differs from the paper.

There is also a separate caution: several replicated costs are below the paper's reported best or even below the stated objective value. These should not be presented as new best-known solutions. A more conservative interpretation is that they may reflect remaining differences in cost accounting, end-of-horizon treatment, source/sink arc handling, or exact inventory timing. Until the evaluator is fully reconciled with the paper's implementation, results below the paper should be treated as evidence of replication-model differences rather than as genuine improvements.

## Remaining Uncertainty About the Heuristic

The main uncertainty is that the paper does not fully specify every operational detail of the heuristic. The current implementation follows the stated BS-GRA-ILS design, but some choices had to be inferred:

| Heuristic component | Current implementation choice | Remaining uncertainty |
|---|---|---|
| Greedy randomized algorithm | Uses deterministic completion plus randomized port selection, with median aggregation over `q = 3` completions. | The paper identifies port-only randomization and median aggregation as strong settings, but exact sampling weights and tie-breaking rules are not fully specified. |
| Vessel selection | Uses the earliest feasible vessel by default. | The authors may use additional tie-breaks or randomized vessel handling in edge cases. |
| Beam search pruning | Keeps the best unique scored successors with `N = 1000` and `w = 2`. | The exact definition of duplicate states and pruning order may differ. |
| Local search | Applies RVND to the beam incumbent before ILS. | The paper suggests local search is central, but does not fully specify whether it is applied to every completed beam solution or only selected incumbents. |
| Simulated annealing in ILS | Uses exponential interpolation between the reported initial and final acceptance probabilities. | The paper reports acceptance probabilities, but not the exact temperature conversion formula. |
| Cost evaluation | Uses a period-based inventory balance and centralized evaluator for construction and local-search moves. | Some cost-accounting details, especially source/sink arcs and end-of-route or end-of-horizon handling, may still differ from the authors' code. |

## Current Assessment

The replication is in a good intermediate state. It now reproduces the paper's results closely enough to support a meaningful comparison, especially because the average gap is near 1% and most individual instances are close. At the same time, the remaining deviations are large enough that the implementation should still be described as an approximate replication rather than an exact one.

The next most useful step would be to focus on the two instances with positive gaps and on validating the evaluator against small hand-checkable schedules. That would help separate true heuristic differences from cost-model differences.

