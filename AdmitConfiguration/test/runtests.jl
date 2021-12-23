using AdmitConfiguration
using CSV
using Test

@testset "AdmitConfiguration.jl" begin
    lp = joinpath(AdmitConfiguration.suitedir, "LocalPreferences.toml")
    tmpfn = tempname()
    isf = isfile(lp)
    try
        if isf
            cp(lp, tmpfn)
        end
        washu = joinpath(dirname(@__DIR__), "examples", "WashU.csv")
        setprograms(washu)
        @test "EEPB" ∈ program_abbreviations
        @test program_lookups["Immunology"] == "IMM"
        @test program_range["PB"] == 2004:2013
        @test program_substitutions["B"] == ["BBSB"]
        @test isfile(lp)
        rm(lp; force=true)
        simple = joinpath(@__DIR__, "data", "simple.csv")
        setprograms(simple; force=true)
        AdmitConfiguration.loadprefs()
        @test "ProgA" ∈ program_abbreviations
        @test "EEPB" ∉ program_abbreviations
    finally
        rm(lp; force=true)
        if isf
            cp(tmpfn, lp)
        end
    end
end