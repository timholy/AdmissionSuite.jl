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
    normapp = NormalizedApplicant(; program, rank=missing, offerdate, decidedate=missing, accept=missing, program_history)

Create an applicant from "natural" units, where rank is an integer and dates are expressed in `Date` format.
Some are required (those without a default value), others are optional:
- `program`: a string encoding the program
- `rank::Int`: the rank of the applicant compared to other applicants to the same program in the same season.
   Use 1 for the top candidate; the bottom candidate should have rank equal to the number of applications received.
- `offerdate`: the date on which an offer was (or might be) extended. E.g., `Date("2021-01-13")`.
- `decidedate`: the date on which the candidate replied with a verdict, or `missing`
- `accept`: `true` if the candidate accepted our offer, `false` if it was turned down, `missing` if it is unknown.

`program_history` should be a dictionary mapping [`ProgramKey`](@ref)s to [`ProgramData`](@ref).
"""
function NormalizedApplicant(; program::AbstractString,
                               rank::Union{Integer,Missing}=missing,
                               offerdate::Date,
                               decidedate::Union{Date,Missing}=missing,
                               accept::Union{Bool,Missing}=missing,
                               program_history)
    program = validateprogram(program)
    pdata = program_history[ProgramKey(program, season(offerdate))]
    normrank = applicant_score(rank, pdata)
    toffer = normdate(offerdate, pdata)
    tdecide = ismissing(decidedate) ? missing : normdate(decidedate, pdata)
    accept = ismissing(accept) ? missing : accept
    return NormalizedApplicant(program, season(offerdate), normrank, toffer, tdecide, accept)
end
# This version is useful for, e.g., reading from a CSV.Row
NormalizedApplicant(applicant; program_history) = NormalizedApplicant(;
    program = applicant.program,
    rank = hasproperty(applicant, :rank) ? applicant.rank : missing,
    offerdate = applicant.offerdate,
    decidedate = hasproperty(applicant, :decidedate) ? applicant.decidedate : missing,
    accept = hasproperty(applicant, :accept) ? applicant.accept : missing,
    program_history
)

ProgramKey(app::NormalizedApplicant) = ProgramKey(app.program, app.season)

"""
    Outcome(ndeclines, naccepts)

Tally of the number of declines and accepts for offers of admission.
"""
struct Outcome
    ndeclines::Int
    naccepts::Int
end
Base.zero(::Type{Outcome}) = Outcome(0, 0)
Base.show(io::IO, outcome::Outcome) = print(io, "(d=", outcome.ndeclines, ", a=", outcome.naccepts, ")")
Base.:+(a::Outcome, b::Outcome) = Outcome(a.ndeclines + b.ndeclines, a.naccepts + b.naccepts)
total(outcome::Outcome) = outcome.ndeclines + outcome.naccepts


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

struct FacultyInvolvement
    program::String
    ninterviews::Int
    ncommittees::Int
end
Base.:+(fi1::FacultyInvolvement, fi2::FacultyInvolvement) = FacultyInvolvement(fi1.program, fi1.ninterviews + fi2.ninterviews, fi1.ncommittees + fi2.ncommittees)
total(fi::FacultyInvolvement) = fi.ninterviews + 10*fi.ncommittees  # the factor of 10 credits the greater time commitment

struct FacultyRecord
    start::Date
    contributions::Vector{FacultyInvolvement}
end
total(fr::FacultyRecord) = sum(total, fr.contributions; init=0)
years(fr::FacultyRecord, yr=year(today())) = yr - year(fr.start) + 1
