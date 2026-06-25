using LinearAlgebra
using Statistics
using MIRPLib

mutable struct LinearQualityModel <: AbstractQualityModel
    xs::Vector{Vector{Float64}}
    ys::Vector{Float64}
    mean::Vector{Float64}
    scale::Vector{Float64}
    beta::Vector{Float64}
    intercept::Float64
    trained::Bool
    min_samples::Int64
    lambda::Float64
end

function LinearQualityModel(; min_samples::Int64 = 16, lambda::Float64 = 1.0)
    return LinearQualityModel(
        Vector{Float64}[],
        Float64[],
        Float64[],
        Float64[],
        Float64[],
        Inf,
        false,
        min_samples,
        lambda,
    )
end

function fit!(model::LinearQualityModel)
    n = length(model.ys)
    n == 0 && return model
    p = length(model.xs[1])
    if n < max(model.min_samples, p + 1)
        model.trained = false
        return model
    end

    X = Matrix{Float64}(undef, n, p)
    for i in 1:n
        X[i, :] = model.xs[i]
    end
    y = collect(model.ys)

    model.mean = vec(mean(X; dims = 1))
    model.scale = vec(std(X; dims = 1))
    model.scale = [scale <= PREDICTIVE_EPS ? 1.0 : scale for scale in model.scale]

    Z = similar(X)
    for j in 1:p
        Z[:, j] = (X[:, j] .- model.mean[j]) ./ model.scale[j]
    end

    ymean = mean(y)
    centered_y = y .- ymean
    ridge = model.lambda * I(p)

    try
        model.beta = (transpose(Z) * Z + ridge) \ (transpose(Z) * centered_y)
        model.intercept = ymean
        model.trained = all(isfinite, model.beta) && isfinite(model.intercept)
    catch
        model.trained = false
    end

    return model
end

function predict_quality(model::LinearQualityModel, mirp::MIRP, solution::Solution)
    x = partial_solution_features(mirp, solution)
    if !model.trained || length(model.beta) != length(x)
        return heuristic_quality_estimate(mirp, solution)
    end

    prediction = model.intercept
    @inbounds for j in eachindex(x)
        prediction += model.beta[j] * ((x[j] - model.mean[j]) / model.scale[j])
    end

    return isfinite(prediction) ? prediction : heuristic_quality_estimate(mirp, solution)
end
