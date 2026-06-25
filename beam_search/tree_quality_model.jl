using Random
using Statistics
using MIRPLib

mutable struct RegressionTreeNode
    feature::Int64
    threshold::Float64
    value::Float64
    left::Union{Nothing, RegressionTreeNode}
    right::Union{Nothing, RegressionTreeNode}
end

function leaf_node(value::Float64)
    return RegressionTreeNode(0, 0.0, value, nothing, nothing)
end

mutable struct TreeQualityModel <: AbstractQualityModel
    xs::Vector{Vector{Float64}}
    ys::Vector{Float64}
    root::Union{Nothing, RegressionTreeNode}
    trained::Bool
    min_samples::Int64
    max_depth::Int64
    min_leaf::Int64
    min_gain::Float64
    feature_subsample_ratio::Float64
    rng::MersenneTwister
end

function TreeQualityModel(;
    min_samples::Int64 = 24,
    max_depth::Int64 = 5,
    min_leaf::Int64 = 6,
    min_gain::Float64 = 1.0e-6,
    feature_subsample_ratio::Float64 = 1.0,
    rng::AbstractRNG = Random.default_rng(),
)
    return TreeQualityModel(
        Vector{Float64}[],
        Float64[],
        nothing,
        false,
        min_samples,
        max_depth,
        min_leaf,
        min_gain,
        feature_subsample_ratio,
        MersenneTwister(rand(rng, UInt)),
    )
end

function feature_subset(p::Int64, ratio::Float64, rng::AbstractRNG)
    count = clamp(ceil(Int64, ratio * p), 1, p)
    count >= p && return collect(1:p)
    return Random.randperm(rng, p)[1:count]
end

function node_sse(sum_y::Float64, sum_y2::Float64, n::Int64)
    n <= 0 && return 0.0
    return max(0.0, sum_y2 - (sum_y * sum_y) / n)
end

function best_split(
    X::Matrix{Float64},
    y::Vector{Float64},
    indices::Vector{Int64},
    features::Vector{Int64},
    min_leaf::Int64,
)
    m = length(indices)
    parent_sum = sum(y[index] for index in indices)
    parent_sum2 = sum(y[index]^2 for index in indices)
    parent_sse = node_sse(parent_sum, parent_sum2, m)

    best_feature = 0
    best_threshold = 0.0
    best_gain = 0.0

    for feature in features
        sorted_indices = sort(indices, by = index -> X[index, feature])
        left_sum = 0.0
        left_sum2 = 0.0

        for split_pos in 1:(m - 1)
            index = sorted_indices[split_pos]
            value = y[index]
            left_sum += value
            left_sum2 += value^2

            left_n = split_pos
            right_n = m - split_pos
            if left_n < min_leaf || right_n < min_leaf
                continue
            end

            current_value = X[index, feature]
            next_value = X[sorted_indices[split_pos + 1], feature]
            if abs(current_value - next_value) <= PREDICTIVE_EPS
                continue
            end

            right_sum = parent_sum - left_sum
            right_sum2 = parent_sum2 - left_sum2
            split_sse = node_sse(left_sum, left_sum2, left_n) +
                node_sse(right_sum, right_sum2, right_n)
            gain = parent_sse - split_sse

            if gain > best_gain
                best_feature = feature
                best_threshold = (current_value + next_value) / 2.0
                best_gain = gain
            end
        end
    end

    return best_feature, best_threshold, best_gain
end

function build_tree(
    X::Matrix{Float64},
    y::Vector{Float64},
    indices::Vector{Int64},
    depth::Int64,
    max_depth::Int64,
    min_leaf::Int64,
    min_gain::Float64,
    feature_subsample_ratio::Float64,
    rng::AbstractRNG,
)
    value = mean(y[index] for index in indices)
    if depth >= max_depth || length(indices) < 2 * min_leaf
        return leaf_node(value)
    end

    features = feature_subset(size(X, 2), feature_subsample_ratio, rng)
    feature, threshold, gain = best_split(X, y, indices, features, min_leaf)
    if feature == 0 || gain <= min_gain
        return leaf_node(value)
    end

    left_indices = Int64[]
    right_indices = Int64[]
    for index in indices
        if X[index, feature] <= threshold
            push!(left_indices, index)
        else
            push!(right_indices, index)
        end
    end

    if length(left_indices) < min_leaf || length(right_indices) < min_leaf
        return leaf_node(value)
    end

    return RegressionTreeNode(
        feature,
        threshold,
        value,
        build_tree(X, y, left_indices, depth + 1, max_depth, min_leaf, min_gain, feature_subsample_ratio, rng),
        build_tree(X, y, right_indices, depth + 1, max_depth, min_leaf, min_gain, feature_subsample_ratio, rng),
    )
end

function fit!(model::TreeQualityModel)
    n = length(model.ys)
    if n < model.min_samples || isempty(model.xs)
        model.trained = false
        return model
    end

    X, y = training_matrix(model)
    model.root = build_tree(
        X,
        y,
        collect(1:n),
        0,
        model.max_depth,
        model.min_leaf,
        model.min_gain,
        model.feature_subsample_ratio,
        model.rng,
    )
    model.trained = model.root !== nothing
    return model
end

function predict_tree(node::RegressionTreeNode, x::Vector{Float64})
    current = node
    while current.feature != 0
        child = x[current.feature] <= current.threshold ? current.left : current.right
        child === nothing && return current.value
        current = child
    end
    return current.value
end

function predict_quality(model::TreeQualityModel, mirp::MIRP, solution::Solution)
    if !model.trained || model.root === nothing
        return heuristic_quality_estimate(mirp, solution)
    end

    x = partial_solution_features(mirp, solution)
    prediction = predict_tree(model.root, x)
    return isfinite(prediction) ? prediction : heuristic_quality_estimate(mirp, solution)
end
