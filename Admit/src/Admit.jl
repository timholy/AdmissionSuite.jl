module Admit

using Dates
using DocStringExtensions
using CSV
using DataFrames
using Measurements
using Statistics
using Random
using DataStructures
using ProgressMeter
using AdmitConfiguration
using ODBC

# Types
export ProgramKey, ProgramData, PersonalData, NormalizedApplicant, Outcome, ProgramYieldPrediction
# Program similarity
export offerdata, yielddata, program_similarity, cached_similarity, yield_errors
# Applicant similarity & matriculation
export match_likelihood, match_function, matriculation_probability, run_simulation, select_applicant, match_correlation
export wait_list_analysis, initial_offers!, add_offers!
# Low-level utilities
export normdate, aggregate, generate_fake_candidates
# I/O
export read_program_history, read_applicant_data, parse_database
# Browser
export manage_offers, runweb

include("types.jl")
include("utils.jl")
include("similarity.jl")
include("predict.jl")
include("io.jl")
include("sql.jl")
include("web.jl")

using PrecompileTools

@setup_workload begin
    struct FakeConn
        applicants::DataFrame
        programs::DataFrame
    end
    DBInterface.execute(conn::FakeConn, tablename::String) =
        tablename == "applicants" ? conn.applicants :
        tablename == "programs"   ? conn.programs   : error(tablename, " unrecognized")
    function swapdata(container::Union{AbstractDict,AbstractSet}, newdata)
        domerge!(c::AbstractDict, d) = merge!(c, d)
        domerge!(c::AbstractSet, d) = !isempty(d) && push!(c, d...)

        orig = copy(container)
        empty!(container)
        domerge!(container, newdata)
        return orig
    end

    # Set up a fake configuration
    sqldata = swapdata(AdmitConfiguration.sql_queries, Dict("applicants" => "applicants",
                                                            "programs" => "programs"))
    colconfig = swapdata(AdmitConfiguration.column_configuration,
                         Dict(# Applicant parsing
                              "name" => "applicant",
                              "app program" => "program",
                              "app season" => "season",
                              "offer date" => "offer date",
                              "rank" => "rank",
                              "accept" => "accept",
                              "decide date" => "decide date",
                              # Program history parsing
                              "prog program" => "program",
                              "prog season" => "season",
                              "slots" => "slots",
                              "napplicants" => "napp",
                              "nmatriculants" => "nmatric")
    )
    progdata = swapdata(AdmitConfiguration.program_abbreviations, Set(["A", "B"]))
    dfmt = AdmitConfiguration.date_fmt[]
    AdmitConfiguration.date_fmt[] = dateformat"mm/dd/yyyy"

    # Fake data
    programs = DataFrame("program" => ["A", "B", "A", "B"],
                     "season" => [2022, 2022, 2023, 2023],
                     "slots" => [2, 2, 2, 2],
                     "nmatric" => [2, 3, 3, 2],
                     "napp" => [20, 20, 20, 20])
    applicants = DataFrame("applicant" => [randstring(8) for _ in 1:16],
                           "season" => [fill(2022, 8); fill(2023, 8)],
                           "program" => [fill("A", 4); fill("B", 4); fill("A", 4); fill("B", 4)],
                           "offer date" => [fill("02/08/2022", 8); fill("02/08/2023", 8)],
                           "decide date" => [fill("04/15/2022", 8); fill(missing, 8)],
                           "rank" => [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4],
                           "accept" => [[true, false, true, false, true, false, true, false]; fill(missing, 8)])
    conn = FakeConn(applicants, programs)

    @compile_workload begin
        parse_database(conn)
        # runweb(conn; tnow=Date(2023, 3, 1))  # this would be nice, but clean shutdown is difficult
    end
    precompile(runweb, (typeof(conn),))
    swapdata(AdmitConfiguration.sql_queries, sqldata)
    swapdata(AdmitConfiguration.column_configuration, colconfig)
    swapdata(AdmitConfiguration.program_abbreviations, progdata)
    AdmitConfiguration.date_fmt[] = dfmt
end

end
