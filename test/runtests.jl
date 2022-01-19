# The following is a workaround for https://github.com/JuliaLang/Pkg.jl/issues/2500
push!(LOAD_PATH, joinpath(dirname(@__DIR__)))
using AdmissionSuite
using Test

# If this next line fails, it means either preferences didn't get set appropriately for testing
# or that Julia's preferences system has a bug
@test !isempty(collect(methods(AdmitConfiguration.getaccept)))

@testset "Admit" begin
    include(joinpath(dirname(@__DIR__), "Admit", "test", "runtests.jl"))
end

@testset "AdmissionTargets" begin
    include(joinpath(dirname(@__DIR__), "AdmissionTargets", "test", "runtests.jl"))
end

# Do these last because they can mess up the configuration
@testset "AdmitConfiguration" begin
    include(joinpath(dirname(@__DIR__), "AdmitConfiguration", "test", "runtests.jl"))
end

pop!(LOAD_PATH)
