## Lower-level utilities

const program_lookups = Dict("Biochemistry" => "B",
                             "Biochemistry, Biophysics, and Structural Biology" => "BBSB",
                             "Biomedical Informatics and Data Science" => "BIDS",
                             "Cancer Biology" => "CB",
                             "Computational and Molecular Biophysics" => "CMB",
                             "Computational and Systems Biology" => "CSB",
                             "Developmental, Regenerative and Stem Cell Biology" => "DRSCB",
                             "Evolution, Ecology and Population Biology" => "EEPB",
                             "Human and Statistical Genetics" => "HSG",
                             "Immunology" => "IMM",
                             "Molecular Cell Biology" => "MCB",
                             "Molecular Genetics and Genomics" => "MGG",
                             "Molecular Microbiology and Microbial Pathogenesis" => "MMMP",
                             "Neurosciences" => "NS",
                             "Plant and Microbial Biosciences" => "PMB")
const program_abbrvs = Set(values(program_lookups))
validateprogram(program::AbstractString) = program ∈ program_abbrvs ? String(program) : program_lookups[program]

date_or_missing(::Missing) = missing
date_or_missing(date::Date) = date
date_or_missing(date::AbstractString) = Date(date)

"""
    normdate(t::Date, pdata::ProgramData)

Express `t` as a fraction of the gap between the first offer date and last decision date as stored in
`pdata` (see [`ProgramData`](@ref)).
"""
function normdate(t::Date, pdata::ProgramData)
    clamp((t - pdata.firstofferdate) / (pdata.lastdecisiondate - pdata.firstofferdate), 0, 1)
end
normdate(t::Real, pdata) = t

applicant_score(rank::Int, pdata) = rank / pdata.napplicants
applicant_score(rank::Missing, pdata) = rank

season(date::Date) = year(date) + (month(date) > 7)
season(applicant::NormalizedApplicant) = applicant.season
