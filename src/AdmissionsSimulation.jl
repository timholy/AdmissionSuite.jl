module AdmissionsSimulation

using Base: String
using Distributions
using Dates
using DocStringExtensions
using CSV

export ProgramKey, ProgramData, NormalizedApplicant
export match_likelihood, match_function, matriculation_probability, select_applicant
export normdate, program_data
export read_program_history, read_applicant_data

"""
`ProgramKey` stores the program name and admissions season.

$(TYPEDFIELDS)
"""
struct ProgramKey
    """
    The program abbreviation. `AdmissionsSimulation.program_lookups` contains the list of valid choices,
    together will full names.
    """
    program::String

    """
    The enrollment year. This is the year in which the applicant's decision was due.
    E.g., if the last date was April 15th, 2021, this would be 2021.
    """
    season::Int16

    ProgramKey(program::AbstractString, season::Integer) = new(validateprogram(program), season)
end
ProgramKey(; program, season) = ProgramKey(program, season)

"""
`ProgramData` stores summary data for a particular program and admissions season.

$(TYPEDFIELDS)
"""
struct ProgramData
    """
    The target number of matriculants, based on applicant pool and training capacity.
    """
    target_raw::Int

    """
    The actual target, correcting for over- or under-recruitment in previous years.
    """
    target_corrected::Int

    """
    The number of matriculated students, or `missing`.
    """
    nmatriculants::Union{Int,Missing}

    """
    The number of applicants received.
    """
    napplicants::Int

    """
    The date on which the first offer was made, essentially the beginning of the decision period for the applicants.
    """
    firstofferdate::Date

    """
    The date on which all applicants must have rendered a decision, or the offer expires.
    """
    lastdecisiondate::Date
end
ProgramData(; slots, nmatriculants=missing, napplicants, firstofferdate, lastdecisiondate) = ProgramData(slots, slots, nmatriculants, napplicants, date_or_missing(firstofferdate), date_or_missing(lastdecisiondate))


"""
`NormalizedApplicant` holds normalized data about an applicant who received, or may receive, an offer of admission.

$(TYPEDFIELDS)
"""
struct NormalizedApplicant
    """
    The abbreviation of the program the applicant was admitted to.
    `AdmissionsSimulation.program_lookups` contains the list of valid choices, together with their full names.
    """
    program::String

    """
    The year in which the applicant's decision was due. E.g., if the last date was April 15th, 2021, this would be 2021.
    """
    season::Int16

    """
    Normalized rank of the applicant: the top applicant has a rank near 0 (e.g., 1/302), and the bottom applicant has rank 1.
    The rank is computed among all applicants, not just those who received an offer of admission.
    """
    normrank::Union{Float32,Missing}

    """
    Normalized date at which the applicant received the offer of admission. 0 = date of first offer of season, 1 = decision date (typically April 15th).
    Candidates who were admitted in the first round would have a value of 0 (or near it), whereas candidates who were on the wait list
    and eventually received offers would have a larger value for this parameter.
    """
    normofferdate::Float32

    """
    Normalized date at which the applicant replied with a decision. This uses the same scale as `normofferdate`.
    Consequently, an applicant who decided almost immediately would have a `normdecidedate` shortly after the `normofferdate`,
    whereas a candidate who decided on the final day will have a value of 1.0.

    Use `missing` if the applicant has not yet decided.
    """
    normdecidedate::Union{Float32,Missing}

    """
    `true` if the applicant accepted our offer, `false` if not. Use `missing` if the applicant has not yet decided.
    """
    accept::Union{Bool,Missing}
end

"""
    normapp = NormalizedApplicant(applicant; program_history)

Convert `applicant` from "natural" units to normalized units. `applicant` may be anything having the following fields:
- `program`: a string encoding the program
- `rank::Int`: the rank of the applicant compared to other applicants to the same program in the same season.
   Use 1 for the top candidate; the bottom candidate should have rank equal to the number of applications received.
- `offerdate`: the date on which an offer was (or might be) extended. E.g., `Date("2021-01-13")`.
- `decidedate`: the date on which the candidate replied with a verdict, or `missing`
- `accept`: `true` if the candidate accepted our offer, `false` if it was turned down, `missing` if it is unknown.

`program_history` should be a dictionary compatible with [`program_data`](@ref).
"""
function NormalizedApplicant(applicant; program_history)
    program = validateprogram(applicant.program)
    pdata = program_data(applicant, program_history)
    normrank = applicant_score(applicant.rank, pdata)
    toffer = normdate(applicant.offerdate, pdata)
    tdecide = hasproperty(applicant, :decidedate) ? normdate(applicant.decidedate, pdata) : missing
    accept = hasproperty(applicant, :accept) ? applicant.accept : missing
    return NormalizedApplicant(program, season(applicant), normrank, toffer, tdecide, accept)
end


"""
    likelihood = match_likelihood(fmatch::Function,
                                  past_applicants::AbstractVector{NormalizedApplicant},
                                  applicant::NormalizedApplicant,
                                  tnow::Real)

Compute the likelihood among `past_applicants` for matching `applicant`. `tnow` is the current date
in normalized form (see [`normdate`](@ref)), and is used to exclude previous applicants who had already made
a decision by `tnow`.

See also: [`match_function`](@ref), [`select_applicant`](@ref).
"""
function match_likelihood(fmatch::Function,
                          past_applicants::AbstractVector{NormalizedApplicant},
                          applicant::NormalizedApplicant,
                          tnow::Real)
    return [fmatch(applicant, app, tnow) for app in past_applicants]
end

"""
    likelihood = match_likelihood(fmatch, past_applicants, applicant, tnow::Date; program_history)

Use this format if supplying `tnow` in `Date` format.
"""
function match_likelihood(fmatch::Function,
                          past_applicants::AbstractVector{NormalizedApplicant},
                          applicant::NormalizedApplicant,
                          tnow::Date;
                          program_history)
    pdata = program_data(applicant, program_history)
    return match_likelihood(fmatch, past_applicants, applicant, normdate(tnow, pdata))
end

"""
    fmatch = match_function(; matchprogram=false, σr=Inf32, σt=Inf32)

Generate a matching function comparing two applicants.

    fmatch(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})

will return a number between 0 and 1, with 1 indicating a perfect match.
`template` is the applicant you wish to find a match for, and `applicant` is a candidate match.
`tnow` is used to exclude `applicant`s who had already decided by `tnow`.

The parameters of `fmatch` are determined by `criteria`:
- `matchprogram::Bool`: if `true`, only students from the same program are considered (all others return 0.0)
- `σr`: the standard deviation of `normrank` (use `Inf` or `missing` if you don't want to consider rank in matches)
- `σt`: the standard deviation of `normofferdate` (use `Inf` or `missing` if you don't want to consider offer date in matches)
"""
function match_function(; matchprogram::Bool=false, σr=Inf32, σt=Inf32)
    σr = convert(Union{Float32,Missing}, σr)
    σt = convert(Union{Float32,Missing}, σt)
    return function(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})
        # Include only applicants that hadn't decided by tnow
        !ismissing(tnow) && tnow > applicant.normdecidedate && return 0.0f0
        # Check whether we need to match the program
        if matchprogram
            template.program !== applicant.program && return 0.0f0
        end
        rankpenalty = coalesce((template.normrank - applicant.normrank)/σr, 0.0f0)^2
        offerdatepenalty = coalesce((template.normofferdate - applicant.normofferdate)/σt, 0.0f0)^2
        return exp(-rankpenalty/2 - offerdatepenalty/2)
    end
end

## Analysis and simulations

"""
    p = matriculation_probability(likelihood, past_applicants)

Compute the probability that applicants weighted by `likelihood` would matriculate into the program, based on the
choices made by `past_applicants`.

`likelihood` can be computed by [`match_likelihood`](@ref).
"""
function matriculation_probability(likelihood, past_applicants)
    axes(likelihood) == axes(past_applicants) || throw(DimensionMismatch("axes of `likelihood` and `past_applicants` must agree"))
    lyes = lno = zero(eltype(likelihood))
    for (l, app) in zip(likelihood, past_applicants)
        if ismissing(app.accept)
            error("past applicants must all be decided")
        elseif app.accept
            lyes += l
        else
            lno += l
        end
    end
    return lyes / (lyes + lno)
end

"""
    past_applicant = select_applicant(clikelihood, past_applicants)

Select a previous applicant from among `past_applicants`, using the cumulative likelihood `clikelihood`.
This can be computed as `cumsum(likelihood)`, where `likelihood` is computed by [`match_likelihood`](@ref).
"""
function select_applicant(clikelihood, past_applicants)
    r = rand() * clikelihood[end]
    idx = searchsortedlast(clikelihood, r) + 1
    return past_applicants[idx]
end

"""
    nmatriculants = run_simulation(pmatric, nsim::Int)

Given a list of candidates with probability of matriculation `pmatric`, perform `nsim` simulations of their
admission decisions and compute the total number of matriculants in each simulation.
"""
function run_simulation(pmatric::AbstractVector{<:Real},
                        nsim::Int)
    function nmatric(ps)
        n = 0
        for p in ps
            n += (rand() <= p)
        end
        return n
    end
    return [nmatric(pmatric) for i = 1:nsim]
end

## I/O

"""
    program_history = read_program_history(filename)
    program_history = read_program_history(f, filename)

Read program history from a file. See "$(@__DIR__)/test/data/programdata.csv" for an example of the format.

The second form allows you to transform each row with `f(row)` before extracting the data. This allows you to
handle input formats that differ from the default.
"""
function read_program_history(f::Function, filename::AbstractString)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("year"=>Int, "program"=>String, "slots"=>Int, "nmatriculants"=>Int, "napplicants"=>Int, "lastdecisiondate"=>Date))
    try
        return Dict(map(rows) do row
            rowf = f(row)
            ProgramKey(season=rowf.year, program=rowf.program) => ProgramData(slots=rowf.slots,
                                                                              nmatriculants=get(rowf, :nmatriculants, missing),
                                                                              napplicants=rowf.napplicants,
                                                                              firstofferdate=date_or_missing(rowf.firstofferdate),
                                                                              lastdecisiondate=rowf.lastdecisiondate)
        end)
    catch
        error("the headers must be year (Int), program (String), slots (Int), napplicants (Int), firstofferdate (Date or missing), lastdecisiondate (Date). The case must match.")
    end
end
read_program_history(filename::AbstractString) = read_program_history(identity, filename)

"""
    past_applicants = read_applicant_data(filename; program_history)
    past_applicants = read_applicant_data(f, filename; program_history)

Read past applicant data from a file. See "$(@__DIR__)/test/data/applicantdata.csv" for an example of the format.

The second form allows you to transform each row with `f(row)` before extracting the data. This allows you to
handle input formats that differ from the default.
"""
function read_applicant_data(filename::AbstractString; program_history)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("program"=>String,"rank"=>Int,"offerdate"=>Date,"decidedate"=>Date,"accept"=>Bool))
    try
        return [NormalizedApplicant(row; program_history) for row in rows]
    catch
        error("the headers must be program (String), rank (Int), offerdate (Date), decidedate (Date), accept (Bool). The case must match.")
    end
end

## Lower-level utilities

# TODO: check against standard abbreviations
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
    normdate(t::Date, pdata)

Express `t` as a fraction of the gap between the first offer date and last decision date as stored in
`pdata` (see [`program_data`](@ref)).
"""
function normdate(t::Date, pdata)
    clamp((t - pdata.firstofferdate) / (pdata.lastdecisiondate - pdata.firstofferdate), 0, 1)
end
normdate(t::Real, pdata) = t

applicant_score(rank::Int, pdata) = rank / pdata.napplicants
applicant_score(rank::Missing, pdata) = rank

"""
    pdata = program_data(applicant, program_history)

Return data for the program and admission season matching `applicant`. One accepted format is the following:

```
program_history = Dict(ProgramKey(season=2021, program="NS") => ProgramData(slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                       ProgramKey(season=2021, program="CB") => ProgramData(slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")),
)
```
"""
program_data(applicant, program_history) = program_history[program_key(applicant, program_history)]

program_key(applicant, ::Dict{ProgramKey}) = ProgramKey(applicant.program, season(applicant))

season(applicant) = hasproperty(applicant, :decidedate) ? year(applicant.decidedate) :
                    year(applicant.offerdate) + (month(applicant.offerdate) > 7)
season(applicant::NormalizedApplicant) = applicant.season

end
