import Pkg

Pkg.activate(@__DIR__)
Pkg.add(["HTTP", "JSON3", "MIRPLib"])
Pkg.instantiate()

println("Julia worker environment is ready.")
