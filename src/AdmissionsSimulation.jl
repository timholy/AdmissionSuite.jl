module AdmissionsSimulation

using Distributions
using Dates
using DocStringExtensions
using CSV
using Measurements
using Statistics
using ProgressMeter

# Types
export ProgramKey, ProgramData, NormalizedApplicant, Outcome, ProgramYieldPrediction
# Targets
export targets, faculty_involvement, aggregate!
# Program similarity
export offerdata, yielddata, program_similarity, cached_similarity
# Applicant similarity & matriculation
export match_likelihood, match_function, matriculation_probability, run_simulation, select_applicant, net_loglike, wait_list_analysis
# Low-level utilities
export normdate
# I/O
export read_program_history, read_applicant_data, read_faculty_data

include("types.jl")
include("utils.jl")
include("targets.jl")
include("similarity.jl")
include("predict.jl")
include("io.jl")

end
