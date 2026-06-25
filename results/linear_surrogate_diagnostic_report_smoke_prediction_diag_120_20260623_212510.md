# Linear surrogate diagnostic run

Generated: 2026-06-23 21:25

This report is intentionally beam-only. Its purpose is to explain construction behavior before LS and ILS obscure the signal.

## Pool summary

| Instance | Scorer | Seed | Beam time | Levels | Pool | Best | Median | Std | Unique top100 | Avg route distance top100 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| LR1_DR02_VC01_V6a | predictive | 1 | 0.19 | 58 | 10 | 33808.97 | 35468.24 | 1068.09 | 10 | 0.155 |

## Files

- Level diagnostics: `results/linear_surrogate_level_diagnostics_smoke_prediction_diag_120_20260623_212510.csv`
- Pool diagnostics: `results/linear_surrogate_pool_diagnostics_smoke_prediction_diag_120_20260623_212510.csv`
- Prediction observations: `results/linear_surrogate_prediction_diagnostics_smoke_prediction_diag_120_20260623_212510.csv`

Prediction observations written: `2150`. Use the level table to show where the learned scorer becomes active and how many GRA completions it avoids. Use the pool table to compare whether linear creates a broader or narrower final candidate distribution. Use the prediction table to compute MAE, RMSE, and rank error between linear predictions and verified GRA scores.
