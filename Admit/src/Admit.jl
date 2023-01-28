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

end