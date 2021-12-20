using AdmissionTargets
using DataFrames
using CSV

# Parse faculty data
facrecs = read_faculty_data("FacultyActivity PhD only.csv")
facrecs = AdmissionTargets.aggregate(facrecs, AdmissionTargets.program_substitutions)
pnames = sort(collect(prog for prog in AdmissionTargets.program_abbreviations if last(AdmissionTargets.program_range[prog]) == typemax(Int)))
program_data_df = CSV.File("program_data.csv") |> DataFrame
const PK = typeof((program="BBSB", season=0))  # fake ProgramKey
const PD = typeof((napplicants=0, target=0))   # fake ProgramData
program_history = Dict{PK,PD}()
for row in eachrow(program_data_df)
    program_history[(program=row."Program", season=row."Season")] = (napplicants=row."napplicants", target=row."target")
end
