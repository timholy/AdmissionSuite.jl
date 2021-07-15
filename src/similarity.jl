
## Program stats

# These are useful for computing cross-program similarity in the matching functions.

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

The output of this function can be cached with [`cached_similarity`](@ref).
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

function fmatch_prog_rank_date(σsel::Real, σyield::Real, σr::Real, σt::Real;
                               offerdata, yielddata)
    progsim = cached_similarity(σsel, σyield; offerdata, yielddata)
    return match_function(; σr, σt, progsim)
end
