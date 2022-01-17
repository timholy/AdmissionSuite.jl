module AdmissionTargets

using Dates
using DocStringExtensions
using AdmitConfiguration
using CSV
using NLsolve
using OrderedCollections

export Service, FacultyRecord
export faculty_affiliations, program_service, calibrate_service, faculty_effort, faculty_involvement, targets
export read_faculty_data

include("types.jl")
include("utils.jl")
include("targets.jl")
include("io.jl")

end
