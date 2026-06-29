using MIRPLib
using OnlineStats
import OnlineStats: coef, fit!, nobs, predict

mutable struct LinearQualityModel{R<:LinReg} <: AbstractQualityModel
    regression::R
    feature_count::Int64
    trained::Bool
    dirty::Bool
    min_samples::Int64
    lambda::Float64
    scratch_features::Vector{Float64}
    scratch_ridge::Vector{Float64}
end

function LinearQualityModel(; min_samples::Int64 = 16, lambda::Float64 = 1.0)
    min_samples < 1 && throw(ArgumentError("min_samples must be positive."))
    lambda < 0.0 && throw(ArgumentError("lambda must be non-negative for ridge regression."))

    regression = LinReg()
    return LinearQualityModel{typeof(regression)}(
        regression,
        0,
        false,
        false,
        min_samples,
        lambda,
        Float64[],
        Float64[],
    )
end

training_sample_count(model::LinearQualityModel) = nobs(model.regression)

function reset_online_stats!(model::LinearQualityModel, p::Int64)
    model.regression = LinReg(p + 1)
    model.feature_count = p
    model.trained = false
    model.dirty = false
    model.scratch_features = Vector{Float64}(undef, p + 1)
    model.scratch_ridge = Vector{Float64}(undef, p + 1)
    return model
end

function add_training_example!(model::LinearQualityModel, x::Vector{Float64}, y::Float64)
    if !isfinite(y) || !all(isfinite, x)
        return model
    end

    p = length(x)
    if model.feature_count == 0
        reset_online_stats!(model, p)
    elseif p != model.feature_count
        throw(ArgumentError("linear quality sample has $(p) features, expected $(model.feature_count)."))
    end

    features = model.scratch_features
    features[1] = 1.0
    @inbounds for j in 1:p
        features[j + 1] = x[j]
    end

    fit!(model.regression, (features, y))
    model.dirty = true
    return model
end

function fit!(model::LinearQualityModel, samples)
    for (x, y) in samples
        add_training_example!(model, x, y)
    end
    return fit!(model)
end

function fit!(model::LinearQualityModel)
    !model.dirty && return model

    n = training_sample_count(model)
    n == 0 && return model
    p = model.feature_count
    if n < max(model.min_samples, p + 1)
        model.trained = false
        return model
    end

    ridge = model.scratch_ridge
    ridge[1] = 0.0
    penalty = model.lambda / n
    @inbounds for j in 2:(p + 1)
        ridge[j] = penalty
    end

    try
        coefficients = coef(model.regression, ridge)
        model.trained = all(isfinite, coefficients)
        model.dirty = false
    catch
        model.trained = false
    end

    return model
end

function predict_quality(model::LinearQualityModel, mirp::MIRP, solution::Solution)
    fit!(model)

    x = partial_solution_features(mirp, solution)
    if !model.trained || model.feature_count != length(x)
        return heuristic_quality_estimate(mirp, solution)
    end

    features = model.scratch_features
    features[1] = 1.0
    @inbounds for j in eachindex(x)
        features[j + 1] = x[j]
    end

    prediction = predict(model.regression, features)
    return isfinite(prediction) ? prediction : heuristic_quality_estimate(mirp, solution)
end
