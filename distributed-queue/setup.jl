import Pkg

Pkg.activate(@__DIR__)
Pkg.instantiate()

println("Julia worker environment is ready.")
