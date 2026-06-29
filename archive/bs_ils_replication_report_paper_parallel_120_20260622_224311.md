# Beam Search + ILS parallel replication report

Generated: 2026-06-22 22:57

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
- ILS iterations: `640`

## Per-instance seed summary

| Instance | Runs | Best ILS | Avg ILS | Best gap | Avg gap | Avg measured time (s) | Avg wall time (s) | Total measured time (s) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | 1 | 33808.95 | 33808.95 | -0.00% | -0.00% | 532.82 | 540.22 | 532.82 |
| LR1_DR02_VC02_V6a | 1 | 78052.08 | 78052.08 | 4.09% | 4.09% | 651.40 | 658.73 | 651.40 |
| LR1_DR02_VC03_V7a | 1 | 40589.73 | 40589.73 | 0.36% | 0.36% | 693.97 | 701.17 | 693.97 |
| LR1_DR02_VC03_V8a | 1 | 43772.61 | 43772.61 | 0.12% | 0.12% | 539.54 | 546.64 | 539.54 |
| LR1_DR02_VC04_V8a | 1 | 41708.66 | 41708.66 | 0.12% | 0.12% | 858.20 | 865.41 | 858.20 |
| LR1_DR02_VC05_V8a | 1 | 36603.23 | 36603.23 | -0.15% | -0.15% | 788.87 | 795.78 | 788.87 |

## Per-run diagnostics

The CSV saved beside this report contains one row per instance/seed run with separate `bs_cost`, `ls_cost`, `ils_cost`, `beam_pool`, `ls_improvements`, `beam_seconds`, `ls_seconds`, `ils_seconds`, `total_seconds`, `wall_seconds`, worker pid, worker run count, and worker RSS memory before/after/after-GC columns.

![Gap comparison](bs_ils_replication_gap_paper_parallel_120_20260622_224311.svg)
