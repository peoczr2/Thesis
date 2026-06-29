# How the ML Surrogate Models Are Trained and Used

This document explains how the predictive beam-search models are trained and how they replace part of the expensive GRA-based node evaluation.

## Objective

The original beam search evaluates each partial successor by completing it with the Greedy Randomized Algorithm (GRA). This gives a useful estimate of how good the partial solution may become, but it is expensive because many successors are completed repeatedly.

The predictive version keeps GRA as a teacher. It uses completed GRA solutions as labelled examples, trains a model online during beam search, and then uses that model to rank most new partial successors cheaply.

The prediction target is:

```text
final solution quality after GRA completion
```

Lower predicted value means a more promising partial solution.

## Where the Training Examples Come From

Training happens inside beam search itself. For a feasible successor node:

1. Extract features from the partial solution before completion.
2. Complete the partial solution with GRA.
3. Store the resulting GRA score as the label.
4. Add `(features, GRA score)` to the model's training set.

In code this is handled by `complete_and_train!` in `beam_search.jl`.

```julia
x = partial_solution_features(mirp, successor)
full_solutions = evaluate(successor, mirp, q; rng = rng)
add_training_example!(model, x, successor.score)
```

The important detail is that `successor.score` is updated by `evaluate(...)`. For the original GRA scorer, this score is the median score of one deterministic GRA completion and `q - 1` randomized GRA completions.

So the model is not trained from artificial labels. It is trained from the same expensive evaluation that the original beam search trusts.

## Online Training Schedule

The model is trained online, level by level:

1. At the beginning, the model has no data.
2. During warmup, beam search still uses GRA scoring.
3. Every GRA-scored successor produces a labelled training example.
4. After each beam level, `fit!(model)` retrains the surrogate using all examples collected so far.
5. Once enough samples exist and the model is marked trained, the beam search switches to predictive scoring for most successors.

The default warmup is:

```julia
surrogate_warmup_levels = 1
surrogate_min_samples = 16
```

For tree and forest models, the actual minimum sample count is raised internally:

| Model | Minimum samples |
|---|---:|
| Linear regression | `16` by default |
| Decision tree | at least `24` |
| Random forest | at least `32` |

## Feature Vector

Each partial solution is converted into a fixed numeric feature vector. The current features are implemented in `partial_solution_features` in `predictive_beam_model.jl`.

| Feature | Meaning |
|---|---|
| `prefix_cost` | Current evaluated cost of the partial route prefix |
| `call_count` | Number of scheduled port calls so far |
| `remaining_horizon` | Fraction of the planning horizon still available after the latest vessel time |
| `next_violation_urgency` | How soon the next inventory violation occurs |
| `min_inventory_slack` | Minimum normalized inventory slack across ports |
| `mean_inventory_slack` | Average normalized inventory slack across ports |
| `vessel_utilization` | Average vessel cargo as a fraction of vessel capacity |
| `vessel_time_spread` | Spread between earliest and latest vessel times |
| `port_imbalance` | Difference between average loading-port fill and unloading-port fill |
| `feasible_arc_ratio` | Fraction of port-vessel pairs currently feasible by route alternation |
| `unique_port_ratio` | Fraction of ports already visited |
| `unique_vessel_ratio` | Fraction of vessels already used |

The features are designed to describe:

- current solution quality,
- inventory risk,
- remaining flexibility,
- vessel utilization,
- balance between loading and unloading ports,
- how much of the routing structure has already been committed.

## Model Choices

The implementation supports three predictive models:

```bash
--surrogate-model=linear
--surrogate-model=tree
--surrogate-model=forest
```

All three models share the same interface:

```julia
add_training_example!(model, x, y)
fit!(model)
predict_quality(model, mirp, solution)
```

This makes them interchangeable inside beam search.

## Linear Regression Model

The linear model is ridge regression. It learns a linear relationship between the partial-solution features and the final GRA-completed score.

Training steps:

1. Build a matrix `X`, where each row is one partial-solution feature vector.
2. Build a vector `y`, where each entry is the final GRA-completed score.
3. Standardize each feature column:

```text
z_j = (x_j - mean_j) / scale_j
```

4. Center the target values around their mean.
5. Solve the ridge-regression system:

```text
beta = (Z'Z + lambda I)^(-1) Z'(y - mean(y))
```

Prediction:

```text
predicted_score = mean(y) + beta dot standardized_features
```

The ridge penalty is controlled by:

```julia
surrogate_lambda = 1.0
```

Why ridge regression is useful here:

- fast to train,
- stable with correlated features,
- cheap to evaluate for every successor,
- works reasonably well with small online training sets.

## Decision Tree Model

The decision tree is a CART-style regression tree.

Training steps:

1. Start with all training examples at the root.
2. Search over feature thresholds.
3. Choose the split that gives the largest reduction in squared error.
4. Recursively split the left and right subsets.
5. Stop when the tree reaches maximum depth, has too few samples, or no split gives enough improvement.

Each leaf stores the average GRA-completed score of the examples in that leaf.

Default tree settings:

| Parameter | Value |
|---|---:|
| `max_depth` | `5` |
| `min_leaf` | `6` |
| `min_gain` | `1.0e-6` |
| `feature_subsample_ratio` | `1.0` |

Prediction:

1. Start at the root.
2. Compare the relevant feature with the node threshold.
3. Move left or right.
4. Repeat until reaching a leaf.
5. Return the leaf's average score.

Why a decision tree is useful here:

- captures nonlinear rules,
- can model threshold effects like "inventory slack is dangerously low",
- is easy to explain in a thesis.

The downside is that a single tree can overfit early online data and prune good branches too aggressively.

## Random Forest Model

The forest is an ensemble of regression trees.

Training steps:

1. Build `n_trees` bootstrap samples from the collected training examples.
2. Train one regression tree on each bootstrap sample.
3. At each split, each tree only considers a random subset of features.
4. Store all trained trees.

Default forest settings:

| Parameter | Value |
|---|---:|
| `n_trees` | controlled by `--surrogate-forest-trees`, default `8` in beam search |
| `max_depth` | `5` |
| `min_leaf` | `6` |
| `sample_ratio` | `0.80` |
| `feature_subsample_ratio` | `0.60` |

Prediction:

```text
predicted_score = average prediction of all trees
```

Why a random forest is useful here:

- more robust than a single tree,
- captures nonlinear interactions,
- reduces variance through averaging.

The downside is runtime. The forest is refit after each beam level, so increasing the number of trees can make the surrogate itself expensive.

## Fallback Prediction Before the Model Is Ready

If a model has not collected enough examples yet, or if fitting fails, prediction falls back to a simple heuristic:

```text
heuristic_score = prefix_cost + urgency_penalty
```

The urgency penalty increases when ports are close to inventory violation. This prevents the algorithm from using meaningless predictions before the model has enough data.

In practice, the beam search mostly uses GRA scoring during warmup and only uses predictive scoring after the model is trained.

## How Prediction Is Used Inside Beam Search

The predictive method does not completely remove GRA. Instead, it uses the model as a filter.

For each beam node:

1. Generate all feasible successors.
2. If the model is not ready, score all successors with GRA.
3. If the model is ready:
   - predict the final quality of every successor,
   - sort successors by predicted score,
   - keep a predictive shortlist,
   - GRA-complete only the shortlisted successors,
   - choose the best `w` children using the real GRA labels.

The shortlist size is:

```text
shortlist_size = surrogate_shortlist_multiplier * w
```

With the default `w = 2` and `surrogate_shortlist_multiplier = 2`, only the best predicted `4` successors per parent are GRA-completed.

This is a hybrid design:

- the model cheaply ranks all successors,
- GRA still validates the most promising candidates,
- the final beam children are chosen from real GRA-completed scores.

This avoids trusting the model blindly.

## Why This Can Be Faster

In the original method, every feasible successor is completed with GRA.

In the predictive method, once the model is trained:

```text
many successors -> cheap model predictions
few shortlisted successors -> expensive GRA completion
```

The intended runtime saving is therefore in the beam phase.

## Why This Can Still Be Slower End-to-End

The comparison runs showed an important interaction: predictive-linear reduced beam time on most instances, but the full BS-LS-ILS pipeline became slower.

The likely reason is that the predictive model changes the pool of complete solutions passed to local search and ILS. Even if the pool has the same size, it may contain solutions that are harder for RVND/ILS to improve.

This means the model can save time in construction but spend more time in improvement.

That is a useful thesis insight:

```text
Learning to rank beam nodes is not enough.
The learned scorer must also control downstream improvement cost.
```

## Current Best Interpretation

The ML surrogate should be described as a beam-search acceleration and diversification mechanism, not yet as a guaranteed end-to-end replacement for GRA.

The strongest result so far is:

- predictive scoring can reduce beam-node evaluation cost,
- it can sometimes find better solution basins,
- but local-search pool management is needed to preserve runtime gains.

The next natural improvement is to combine predictive beam scoring with a smaller or smarter local-search pool, for example improving only the best `100`, `200`, or `500` completed candidates instead of all `1000`.
