module AdmissionsSimulation

using Distributions
using Dates
using DocStringExtensions
using CSV
using Measurements
using Statistics
using DataStructures
using NLsolve
using ProgressMeter

# Types
export ProgramKey, ProgramData, PersonalData, NormalizedApplicant, Outcome, ProgramYieldPrediction, Service, FacultyRecord
# Targets
export faculty_affiliations, program_service, calibrate_service, faculty_effort, faculty_involvement, targets, initial_offers!, add_offers!
# Program similarity
export offerdata, yielddata, program_similarity, cached_similarity
# Applicant similarity & matriculation
export match_likelihood, match_function, matriculation_probability, run_simulation, select_applicant, match_correlation, wait_list_analysis
# Low-level utilities
export normdate, aggregate, generate_fake_candidates
# I/O
export read_program_history, read_applicant_data, read_faculty_data

include("types.jl")
include("utils.jl")
include("targets.jl")
include("similarity.jl")
include("predict.jl")
include("io.jl")
include("web.jl")

end
