# Beam Search + ILS parallel replication report

Generated: 2026-06-23 10:11

## Batch settings

- Horizon: `120`
- Seeds per instance: `1`
- Total runs: `6`
- Single-thread workers: `6`
- GC between runs: `true`
- Restart workers every N runs: `0` (`0` means disabled)
- Beam nodes per level `N = 1000`
- Maximum children per node `w = 2`
- Greedy randomized completions per successor `q = 3`
- Beam node scorer: `predictive`
- Predictive surrogate model: `linear`
- Predictive shortlist multiplier: `2`
- ILS iterations: `640`

## Per-instance seed summary

| Instance | Runs | Best ILS | Avg ILS | Best gap | Avg gap | Avg measured time (s) | Avg wall time (s) | Total measured time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 1 | 33808.95 | 33808.95 | -0.00% | -0.00% | 916.76 | 925.95 | 916.76 |
| LR1_DR02_VC02_V6a | 1 | 77928.08 | 77928.08 | 3.93% | 3.93% | 1335.03 | 1344.20 | 1335.03 |
| LR1_DR02_VC03_V7a | 1 | 40593.57 | 40593.57 | 0.36% | 0.36% | 1394.23 | 1403.64 | 1394.23 |
| LR1_DR02_VC03_V8a | 1 | 43772.61 | 43772.61 | 0.12% | 0.12% | 883.71 | 893.36 | 883.71 |
| LR1_DR02_VC04_V8a | 1 | 41708.68 | 41708.68 | 0.12% | 0.12% | 2366.28 | 2375.64 | 2366.28 |
| LR1_DR02_VC05_V8a | 1 | 36603.23 | 36603.23 | -0.15% | -0.15% | 1770.32 | 1779.52 | 1770.32 |

## Per-run diagnostics

The CSV saved beside this report contains one row per instance/seed run with separate `bs_cost`, `ls_cost`, `ils_cost`, `beam_pool`, `ls_improvements`, `beam_seconds`, `ls_seconds`, `ils_seconds`, `total_seconds`, `wall_seconds`, worker pid, worker run count, and worker RSS memory before/after/after-GC columns.

![Gap comparison](bs_ils_replication_gap_mlcmp_linear_120_20260623_093113.svg)
