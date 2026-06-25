using Random
using Statistics
using MIRPLib

mutable struct ForestQualityModel <: AbstractQualityModel
    xs::Vector{Vector{Float64}}
    ys::Vector{Float64}
    trees::Vector{RegressionTreeNode}
    trained::Bool
    min_samples::Int64
    n_trees::Int64
    max_depth::Int64
    min_leaf::Int64
    min_gain::Float64
    sample_ratio::Float64
    feature_subsample_ratio::Float64
    rng::MersenneTwister
end

function ForestQualityModel(;
    min_samples::Int64 = 32,
    n_trees::Int64 = 12,
    max_depth::Int64 = 5,
    min_leaf::Int64 = 6,
    min_gain::Float64 = 1.0e-6,
    sample_ratio::Float64 = 0.80,
    feature_subsample_ratio::Float64 = 0.60,
    rng::AbstractRNG = Random.default_rng(),
)
    return ForestQualityModel(
        Vector{Float64}[],
        Float64[],
        RegressionTreeNode[],
        false,
        min_samples,
        n_trees,
        max_depth,
        min_leaf,
        min_gain,
        sample_ratio,
        feature_subsample_ratio,
        MersenneTwister(rand(rng, UInt)),
    )
end

function fit!(model::ForestQualityModel)
    n = length(model.ys)
    if n < model.min_samples || isempty(model.xs)
        model.trained = false
        return model
    end

    X, y = training_matrix(model)
    empty!(model.trees)
    sample_size = clamp(round(Int64, model.sample_ratio * n), model.min_samples, n)

    for _ in 1:model.n_trees
        indices = [rand(model.rng, 1:n) for _ in 1:sample_size]
        push!(
            model.trees,
            build_tree(
                X,
                y,
                indices,
                0,
                model.max_depth,
                model.min_leaf,
                model.min_gain,
                model.feature_subsample_ratio,
                model.rng,
            ),
        )
    end

    model.trained = !isempty(model.trees)
    return model
end

function predict_quality(model::ForestQualityModel, mirp::MIRP, solution::Solution)
    if !model.trained || isempty(model.trees)
        return heuristic_quality_estimate(mirp, solution)
    end

    x = partial_solution_features(mirp, solution)
    prediction_sum = 0.0
    @inbounds for tree in model.trees
        prediction_sum += predict_tree(tree, x)
    end
    prediction = prediction_sum / length(model.trees)
    return isfinite(prediction) ? prediction : heuristic_quality_estimate(mirp, solution)
end
