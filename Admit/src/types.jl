# A list of pairs
const ListPairs{K,V} = Union{AbstractDict{K,V},AbstractVector{Pair{K,V}}}

"""
`ProgramKey` stores the program name and admissions season.

$(TYPEDFIELDS)
"""
struct ProgramKey
    """
    The program abbreviation. `Admit.program_lookups` contains the list of valid choices,
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
ProgramKey(program::AbstractString, date::Date) = ProgramKey(program, season(date))

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
ProgramData(; slots=0, nmatriculants=0, napplicants=0, firstofferdate=today(), lastdecisiondate=Date(0)) = ProgramData(slots, slots, nmatriculants, napplicants, date_or_missing(firstofferdate), date_or_missing(lastdecisiondate))
Base.:+(a::ProgramData, b::ProgramData) = ProgramData(a.target_raw + b.target_raw,
                                                      a.target_corrected + b.target_corrected,
                                                      a.nmatriculants + b.nmatriculants,
                                                      a.napplicants + b.napplicants,
                                                      today(),
                                                      Date(0))

"""
`PersonalData` holds relevant data about an individual applicant.

$(TYPEDFIELDS)
"""
struct PersonalData
    """
    Name of the applicant
    """
    name::String

    """
    `true` if an applicant is an underrepresented minority, disadvantaged, or disabled.
    """
    urmdd::Union{Bool,Missing}

    """
    `true` if an applicant is not a US citizen or permanent resident.
    """
    foreign::Union{Bool,Missing}
end

function PersonalData(name=""; urmdd::Union{Bool,Missing}=missing,
                               foreign::Union{Bool,Missing}=missing)
    PersonalData(name, urmdd, foreign)
end
function PersonalData(pd::PersonalData; kwargs...)
    name = haskey(kwargs, :name) ? kwargs[:name] : pd.name
    urmdd = haskey(kwargs, :urmdd) ? kwargs[:urmdd] : pd.urmdd
    foreign = haskey(kwargs, :foreign) ? kwargs[:foreign] : pd.foreign
    return PersonalData(name, urmdd, foreign)
end

function Base.show(io::IO, pd::PersonalData)
    !isempty(pd.name) && print(io, pd.name, ", ")
    !ismissing(pd.urmdd) && print(io, "urmdd=", pd.urmdd, ", ")
    !ismissing(pd.foreign) && print(io, "foreign=", pd.foreign, ", ")
end

"""
`NormalizedApplicant` holds normalized data about an applicant who received, or may receive, an offer of admission.

$(TYPEDFIELDS)
"""
struct NormalizedApplicant
    """
    Individual data about the applicant, see [`PersonalData`](@ref).
    """
    applicantdata::PersonalData

    """
    The abbreviation of the program the applicant was admitted to.
    `Admit.program_lookups` contains the list of valid choices, together with their full names.
    """
    program::String

    """
    The year in which the applicant's decision was due. E.g., if the decision deadline was April 15th, 2021, this would be 2021.
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
    normofferdate::Union{Float32,Missing}

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
    normapp = NormalizedApplicant(; program, urmdd=missing, foreign=missing, rank=missing, offerdate, decidedate=missing, accept=missing, program_history)

Create an applicant from "natural" units, where rank is an integer and dates are expressed in `Date` format.
Some are required (those without a default value), others are optional:
- `program`: a string encoding the program
- `urmdd`: `true` if applicant is a URM, disadvantaged, or disabled
- `foreign`: `true` if applicant is not a citizen or permanent resident
- `rank::Int`: the rank of the applicant compared to other applicants to the same program in the same season.
   Use 1 for the top candidate; the bottom candidate should have rank equal to the number of applications received.
- `offerdate`: the date on which an offer was (or might be) extended. E.g., `Date("2021-01-13")`.
- `decidedate`: the date on which the candidate replied with a verdict, or `missing`
- `accept`: `true` if the candidate accepted our offer, `false` if it was turned down, `missing` if it is unknown.

`program_history` should be a dictionary mapping [`ProgramKey`](@ref)s to [`ProgramData`](@ref).
"""
function NormalizedApplicant(; name::AbstractString="",
                               program::AbstractString,
                               urmdd::Union{Bool,Missing}=missing,
                               foreign::Union{Bool,Missing}=missing,
                               rank::Union{Integer,Missing}=missing,
                               offerdate::Union{Date,Missing}=missing,
                               decidedate::Union{Date,Missing}=missing,
                               accept::Union{Bool,Missing}=missing,
                               program_history)
    program = validateprogram(program)
    pdata = program_history[ProgramKey(program, season(offerdate))]
    normrank = applicant_score(rank, pdata)
    toffer = ismissing(offerdate) ? missing : normdate(offerdate, pdata)
    tdecide = ismissing(decidedate) ? missing : normdate(decidedate, pdata)
    accept = ismissing(accept) ? missing : accept
    return NormalizedApplicant(PersonalData(name; urmdd, foreign), program, season(offerdate), normrank, toffer, tdecide, accept)
end
# replacing/updating values
function NormalizedApplicant(applicant::NormalizedApplicant; kwargs...)
    _season, normofferdate, normdecidedate = applicant.season, applicant.normofferdate, applicant.normdecidedate
    program = haskey(kwargs, :program) ? validateprogram(kwargs[:program]) : applicant.program
    normrank = applicant.normrank
    if haskey(kwargs, :program_history)
        program_history = kwargs[:program_history]
        if haskey(kwargs, :offerdate)
            _season = season(kwargs[:offerdate])
        end
        pdata = program_history[ProgramKey(program, _season)]
        if haskey(kwargs, :offerdate)
            normofferdate = normdate(kwargs[:offerdate], program_history)
        end
        if haskey(kwargs, :decidedate)
            normdecidedate = normdate(kwargs[:decidedate], program_history)
        end
        if haskey(kwargs, :rank)
            normrank = applicant_score(kwargs[:rank], pdata)
        end
    else
        haskey(kwargs, :offerdate) || haskey(kwargs, :decidedate) || haskey(kwargs, :rank) &&
            error("supplying offerdate, decidedate, or rank requires `program_history`")
    end

    NormalizedApplicant(
        PersonalData(applicant.applicantdata; kwargs...),
        program,
        _season,
        normrank,
        normofferdate,
        normdecidedate,
        haskey(kwargs, :accept) ? kwargs[:accept] : applicant.accept,
    )
end

# This version is useful for, e.g., reading from a CSV.Row (see test/data)
NormalizedApplicant(applicant; program_history) = NormalizedApplicant(;
    program = applicant.program,
    urmdd = hasproperty(applicant, :urm) ? applicant.urm : missing,
    foreign = hasproperty(applicant, :foreign) ? applicant.foreign : missing,
    rank = hasproperty(applicant, :rank) ? applicant.rank : missing,
    offerdate = applicant.offerdate,
    decidedate = hasproperty(applicant, :decidedate) ? applicant.decidedate : missing,
    accept = hasproperty(applicant, :accept) ? applicant.accept : missing,
    program_history
)

function Base.show(io::IO, app::NormalizedApplicant)
    print(io, "NormalizedApplicant(")
    print(io, app.applicantdata)
    print(io, app.program, ", ")
    print(io, app.season, ", ")
    !ismissing(app.normrank) && print(io, "normrank=", app.normrank, ", ")
    print(io, "normofferdate=", app.normofferdate, ", ")
    !ismissing(app.normdecidedate) && print(io, "normdecidedate=", app.normdecidedate, ", ")
    !ismissing(app.accept) && print(io, "accept=", app.accept)
    print(io, ")")
end

ProgramKey(app::NormalizedApplicant) = ProgramKey(app.program, app.season)

"""
    Outcome(ndeclines, naccepts)

Tally of the number of declines and accepts for offers of admission.
"""
struct Outcome
    ndeclines::Int
    naccepts::Int
end
Outcome() = Outcome(0, 0)
Base.zero(::Type{Outcome}) = Outcome()
Base.show(io::IO, outcome::Outcome) = print(io, "(d=", outcome.ndeclines, ", a=", outcome.naccepts, ")")
Base.:+(a::Outcome, b::Outcome) = Outcome(a.ndeclines + b.ndeclines, a.naccepts + b.naccepts)
total(outcome::Outcome) = outcome.ndeclines + outcome.naccepts

function Outcome(app::NormalizedApplicant)
    accept = app.accept
    return Outcome(accept===false, accept===true)
end

"""
`ProgramYieldPrediction` records mid-season predictions and data for a particular program.

$(TYPEDFIELDS)
"""
struct ProgramYieldPrediction
    """
    The predicted number of matriculants.
    """
    nmatriculants::Measurement{Float32}

    """
    The program's priority for receiving wait list offers. The program with the highest priority should get the next offer.
    Priority is computed as `deficit/stddev`, where `deficit` is the predicted undershoot (which might be negative if the program
    is predicted to overshoot) and `stddev` is the square root of the target (Poisson noise).
    Thus, programs are prioritized by the significance of the deficit.
    """
    priority::Float32

    """
    The two-tailed p-value of the actual outcome (if supplied). This includes the effects of any future wait-list offers.
    """
    poutcome::Union{Float32,Missing}
end
ProgramYieldPrediction(nmatriculants, priority) = ProgramYieldPrediction(nmatriculants, priority, missing)

