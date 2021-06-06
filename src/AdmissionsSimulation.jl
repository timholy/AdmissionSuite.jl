module AdmissionsSimulation

using Distributions
using Dates
using DocStringExtensions
using CSV
using Measurements
using Statistics
using ProgressMeter

export ProgramKey, ProgramData, NormalizedApplicant
export Outcome, ProgramYieldPrediction, offerdata, yielddata, program_similarity, cached_similarity
export match_likelihood, match_function, matriculation_probability, select_applicant, net_probability, wait_list_offers
export normdate
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

## Program stats

# These are useful for computing cross-program similarity in the matching functions.

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

myzero(::Type{NTuple{N,T}}) where {N,T} = ntuple(_ -> myzero(T), N)
myzero(::Type{T}) where T = zero(T)
# myplus(a::NTuple{N}, b::NTuple{N}) where N = myplus.(a, b)
# myplus(a, b) = a + b

makekey(::Dict{ProgramKey}, key::ProgramKey) = key
makekey(::Dict{String}, key::ProgramKey) = key.program

# function addoffer!(offers, applicant)
#     key = makekey(offers, ProgramKey(applicant))
#     count = get(offers, key, myzero(valtype(offers)))
#     N = length(count)
#     j = max(1, ceil(Int, N*applicant.normofferdate))
#     newcount = ntuple(i -> count[i] + (i == j), N)
#     offers[key] = newcount
# end

"""
    offerdata(applicants, program_history)

Summarize application and offer data for each program. The output is a dictionary mapping `programname => (noffers, napplicants)`.
The program selectivity is the ratio `noffers/napplicants`.
"""
function offerdata(applicants, program_history)
    usedkeys = Set{ProgramKey}()
    cumoffers = Dict{String,Int}()
    cumapps = Dict{String,Int}()
    for app in applicants   # doing everything triggered by applicants ensures we match years
        pk = ProgramKey(app)
        key = pk.program
        if pk ∉ usedkeys
            push!(usedkeys, pk)
            cumapps[key] = get(cumapps, key, 0) + program_history[pk].napplicants
        end
        cumoffers[key] = get(cumoffers, key, 0) + 1
    end
    result = Dict{String, Tuple{Int,Int}}()
    for (key, _) in cumoffers
        result[key] = (cumoffers[key], cumapps[key])
    end
    return result
end

addoutcome(count::Outcome, accept::Bool) = Outcome(count.ndeclines + !accept, count.naccepts + accept)
function addoutcome!(outcomes, applicant)
    key = makekey(outcomes, ProgramKey(applicant))
    count = get(outcomes, key, myzero(valtype(outcomes)))
    if valtype(outcomes) === Outcome
        outcomes[key] = addoutcome(count, applicant.accept)
    else
        N = length(count)
        j = max(1, ceil(Int, N * (ismissing(applicant.normdecidedate) ? 1.0f0 : applicant.normdecidedate)))
        newcount = ntuple(i -> i == j ? addoutcome(count[i], applicant.accept) : count[i], N)
        outcomes[key] = newcount
    end
end

"""
    yielddata(Outcome, applicants)
    yielddata(Tuple{Outcome,Outcome,Outcome}, applicants)

Compute the outcome of offers of admission for each program. `applicants` should be a list of [`NormalizedApplicant`](@ref).
The first form computes the [`Outcome`](@ref) for the entire season, and the second breaks the season up into epochs
of equal duration and computes the outcome for each epoch separately. If provided, [`program_similarity`](@ref) will make use of
the time-dependence of the yield.
"""
function yielddata(::Type{Y}, applicants) where Y <: Union{Outcome,Tuple{Outcome,Vararg{Outcome}}}
    result = Dict{String,Y}()
    for applicant in applicants
        addoutcome!(result, applicant)
    end
    return result
end

## Matching

"""
    program_similarity(program1::AbstractString, program2::AbstractString;
                       σsel=Inf32, σyield=Inf32, offerdata, yielddata)

Compute the similarity between `program1` and `program2`, based on selectivity (fraction of applicants who are admitted)
and yield (fraction of offers that get accepted). The similarity ranges between 0 and 1, with 1 corresponding to
identical programs.

The keyword arguments are the parameters controlling the similarity computation.
`offerdata` and `yielddata` are the outputs of two functions of the same name ([`offerdata`](@ref) and [`yielddata`](@ref)).
`σsel` and `σyield` are the standard deviations of selectivity and yield. The similarity is computed as

```math
\\exp\\left(-\\frac{(s₁ - s₂)²}{2σ_\\text{sel}²} - \\frac{(y₁ - y₂)²}{2σ_\\text{yield}²}\\right).
```
"""
function program_similarity(program1::AbstractString, program2::AbstractString;
                            σsel=Inf32, σyield=Inf32, offerdata, yielddata)
    selpenalty = yieldpenalty = 0.0f0
    if program1 != program2
        if offerdata !== nothing
            o1, a1 = offerdata[program1]
            o2, a2 = offerdata[program2]
            selpenalty = ((o1/a1 - o2/a2)/σsel)^2
        end
        if yielddata !== nothing
            y1 = yielddata[program1]
            y2 = yielddata[program2]
            ty1 = total(sum(y1))
            ty2 = total(sum(y2))
            for (yy1, yy2) in zip(y1, y2)
                yieldpenalty += (yy1.ndeclines/ty1 - yy2.ndeclines/ty2)^2 + (yy1.naccepts/ty1 - yy2.naccepts/ty2)^2
            end
            yieldpenalty /= σyield^2
        end
    end
    return exp(-selpenalty/2 - yieldpenalty/2)
end

default_similarity(program1, program2) = program1 == program2

"""
    fsim = cached_similarity(σsel, σyield; offerdata, yielddata)

Cache the result of [`program_similarity`](@ref), creating a function `fsim(program1::AbstractString, program2::AbstractString)`
to compute the similarity between `program1` and `program2`.
"""
function cached_similarity(σsel, σyield; offerdata, yielddata)
    pnames = sort(collect(keys(yielddata)))
    cached_similarity = Dict{Tuple{String,String},Float32}()
    for i = 1:length(pnames)
        nᵢ = pnames[i]
        for j = 1:i
            nⱼ = pnames[j]
            key = nᵢ <= nⱼ ? (nᵢ, nⱼ) : (nⱼ, nᵢ)
            cached_similarity[key] = program_similarity(nᵢ, nⱼ; σsel, σyield, offerdata, yielddata)
        end
    end
    function progsim(p1::AbstractString, p2::AbstractString)
        key = p1 <= p2 ? (p1, p2) : (p2, p1)
        return get(cached_similarity, key, 1.0f0)  # if no program matches, match against all
    end
    return progsim
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
    pdata = program_history[ProgramKey(applicant)]
    return match_likelihood(fmatch, past_applicants, applicant, normdate(tnow, pdata))
end

"""
    fmatch = match_function(; σr=Inf32, σt=Inf32, progsim=default_similarity)

Generate a matching function comparing two applicants.

    fmatch(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})

will return a number between 0 and 1, with 1 indicating a perfect match.
`template` is the applicant you wish to find a match for, and `applicant` is a candidate match.
`tnow` is used to exclude `applicant`s who had already decided by `tnow`.

The parameters of `fmatch` are determined by `criteria`:
- `σr`: the standard deviation of `normrank` (use `Inf` or `missing` if you don't want to consider rank in matches)
- `σt`: the standard deviation of `normofferdate` (use `Inf` or `missing` if you don't want to consider offer date in matches)
- `progsim`: a function `progsim(program1, program2)` computing the "similarity" between programs.
  See [`cached_similarity`](@ref).
  The default returns `true` if `program1 == program2` and `false` otherwise.
"""
function match_function(; σr=Inf32, σt=Inf32, progsim=default_similarity)
    σr = convert(Union{Float32,Missing}, σr)
    σt = convert(Union{Float32,Missing}, σt)
    return function(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})
        # Include only applicants that hadn't decided by tnow
        !ismissing(tnow) && !ismissing(applicant.normdecidedate) && tnow > applicant.normdecidedate && return 0.0f0
        progcoef = progsim(template.program, applicant.program)
        rankpenalty = coalesce((template.normrank - applicant.normrank)/σr, 0.0f0)^2
        offerdatepenalty = coalesce((template.normofferdate - applicant.normofferdate)/σt, 0.0f0)^2
        return progcoef * exp(-rankpenalty/2 - offerdatepenalty/2)
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
    nmatriculants = run_simulation(pmatric::AbstractVector, nsim::Int=100)

Given a list of candidates each with probability of matriculation `pmatric[i]`, perform `nsim` simulations of their
admission decisions and compute the total number of matriculants in each simulation.
"""
function run_simulation(pmatric::AbstractVector{<:Real},
                        nsim::Int=100)
    function nmatric(ps)
        n = 0
        for p in ps
            n += (rand() <= p)
        end
        return n
    end
    return [nmatric(pmatric) for i = 1:nsim]
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

priority(pred, target) = (target - pred)/sqrt(target)

"""
    nmatric, progstatus = wait_list_offers(fmatch::Function,
                                           past_applicants::AbstractVector{NormalizedApplicant},
                                           applicants::AbstractVector{NormalizedApplicant},
                                           tnow::Date;
                                           program_history,
                                           actual_yield=nothing)

Compute the estimated number `nmatric` of matriculants and the program-specific yield prediction and wait-list priority, `progstatus`.
`progstatus` is a mapping `progname => progyp::ProgramYieldPrediction` (see [`ProgramYieldPrediction`](@ref)).

The arguments are similarly to [`match_likelihood`](@ref).
"""
function wait_list_offers(fmatch::Function,
                          past_applicants::AbstractVector{NormalizedApplicant},
                          applicants::AbstractVector{NormalizedApplicant},
                          tnow::Union{Date,Real};
                          program_history,
                          actual_yield=nothing)
    yr = season(only(unique(season, applicants)))
    progyields = Dict{String,ProgramYieldPrediction}()
    nmatric = 0.0f0
    for (progkey, progdata) in program_history
        progkey.season == yr || continue
        progname = progkey.program
        ntnow = isa(tnow, Date) ? normdate(tnow, progdata) : tnow
        # Select applicants to this program who already have an offer
        papplicants = filter(app -> app.program == progname && (app.normofferdate < ntnow || iszero(app.normofferdate)), applicants)
        pmatric = map(papplicants) do applicant
            applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
            like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
            return matriculation_probability(like, past_applicants)
        end
        prognmatric = sum(pmatric)
        simnmatric = run_simulation(pmatric, 10^4)
        estmatric = round(mean(simnmatric); digits=1) ± round(std(simnmatric); digits=1)
        progtarget = progdata.target_corrected
        poutcome = missing
        if actual_yield !== nothing
            wlapplicants = filter(app -> app.program == progname && (app.normofferdate >= ntnow && !iszero(app.normofferdate)), applicants)
            for applicant in wlapplicants
                like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
                push!(pmatric, matriculation_probability(like, past_applicants))
            end
            wlnmatric = sum(pmatric)
            simnmatric = run_simulation(pmatric, 10^4)
            yld = actual_yield[progname]
            Δyld = abs(yld - wlnmatric)
            poutcome = sum(abs.(simnmatric .- wlnmatric) .>= Δyld)/length(simnmatric)
        end
        progyields[progname] = ProgramYieldPrediction(estmatric, priority(prognmatric, progtarget), poutcome)
        nmatric += prognmatric
    end
    return nmatric, progyields
end

## Model training

# Tune the match parameters to optimize accuracy of prediction

function net_probability(σsel::Real, σyield::Real, σr::Real, σt::Real;
                         applicants, past_applicants, offerdata, yielddata,
                         #= fraction of prior applicants that must match =# rmatch_floor=0.01)
    progsim = cached_similarity(σsel, σyield; offerdata, yielddata)
    fmatch = match_function(; σr, σt, progsim)
    cprob = 0.0f0
    for applicant in applicants
        like = match_likelihood(fmatch, past_applicants, applicant, 0.0f0)
        sum(like) < rmatch_floor*length(past_applicants) && return -Inf32
        p = matriculation_probability(like, past_applicants)
        isnan(p) && continue
        cprob += applicant.accept ? p : -p
    end
    return cprob
end

"""
    net_probability(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;
                    applicants, program_history)

Compute the net probability of prediction using historical data. For each year in `program_history` other than the earliest,
use prior data to predict the probability of matriculation for each applicant. If `p` is the probability for a particular applicant,
it contributes positively (`+p`) if the offer was accepted, and negatively (`-p`) if the offer was declined.
Thus, successful prediction maximizes the net probability.

The `σ` lists contain the values that will be used to compute accuracy; the return value is a 4-dimensional array evaluating
the net probability for all possible combinations of these parameters. `σsel` and `σyield` will be used by [`cached_similarity`](@ref)
to determine program similarity; `σr` and `σs` will be used to measure applicant similarity.

Tuning essentially corresponds to picking the index of the entry of the return value and then setting each parameter accordingly:

```julia
np = net_probability(σsels, σyields, σrs, σts; applicants, program_history)
idx = argmax(np)
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]
```
"""
function net_probability(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;
                         applicants, program_history, kwargs...)
    yrmin, yrmax = extrema(pk->pk.season, keys(program_history))
    cprob = zeros(Float32, length(σsels), length(σyields), length(σrs), length(σts))
    progress = Progress((yrmax - yrmin)*length(σrs)*length(σts); desc="Computing accuracy vs parameters for each year (progress slows in later years): ")
    for yr = yrmin+1:yrmax
        yrapplicants = filter(app -> app.season == yr, applicants)
        prevapplicants = filter(app -> app.season < yr, applicants)
        od = offerdata(prevapplicants, program_history)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, prevapplicants)
        for k in eachindex(σrs), l in eachindex(σts)
            for i in eachindex(σsels), j in eachindex(σyields)
                cprob[i,j,k,l] += net_probability(σsels[i], σyields[j], σrs[k], σts[l];
                                                applicants=yrapplicants, past_applicants=prevapplicants,
                                                offerdata=od, yielddata=yd, kwargs...)
            end
            ProgressMeter.next!(progress; showvalues=[(:yr, yr)])
        end
    end
    return cprob
end

## I/O

"""
    program_history = read_program_history(filename)

Read program history from a file. See "$(@__DIR__)/test/data/programdata.csv" for an example of the format.

The second form allows you to transform each row with `f(row)` before extracting the data. This allows you to
handle input formats that differ from the default.
"""
function read_program_history(filename::AbstractString)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("year"=>Int, "program"=>String, "slots"=>Int, "nmatriculants"=>Int, "napplicants"=>Int, "lastdecisiondate"=>Date))
    try
        return Dict(map(rows) do row
            ProgramKey(season=row.year, program=row.program) => ProgramData(slots=row.slots,
                                                                            nmatriculants=get(row, :nmatriculants, missing),
                                                                            napplicants=row.napplicants,
                                                                            firstofferdate=date_or_missing(row.firstofferdate),
                                                                            lastdecisiondate=row.lastdecisiondate)
        end)
    catch
        error("the headers must be year (Int), program (String), slots (Int), napplicants (Int), firstofferdate (Date or missing), lastdecisiondate (Date). The case must match.")
    end
end

"""
    past_applicants = read_applicant_data(filename; program_history)

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

end
