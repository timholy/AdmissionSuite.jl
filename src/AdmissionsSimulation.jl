module AdmissionsSimulation

using Distributions
using Dates
using DocStringExtensions

export NormalizedApplicant, match_likelihood, match_function, matriculation_probability, normdate, program_data, select_applicant

"""
`NormalizedApplicant` holds normalized data about an applicant who received, or may receive, an offer of admission.

$(TYPEDFIELDS)
"""
struct NormalizedApplicant
    """
    A symbol encoding the program the applicant was admitted to.
    """
    program::Symbol

    """
    The year in which the applicant's decision was due. E.g., if the last date was April 15th, 2021, this would be 2021.
    """
    season::Int16

    """
    Normalized rank of the applicant: the top applicant has a rank near 0 (e.g., 1/302), and the bottom applicant has rank 1.
    The rank is computed among all applicants, not just those who received an offer of admission.
    """
    normrank::Float32

    """
    Normalized date at which the applicant received the offer of admission. 0 = date of first offer of season, 1 = decision date (typically April 15th).
    Candidates who were admitted in the first round would have a value of 0 (or near it), whereas candidates who were on the wait list
    and eventually received offers would have a larger value for this parameter.
    """
    normofferdate::Float32

    """
    Normalized date at which the applicant replied with a decision. This uses the same scale as `normofferdate`.
    Consequently, an applicant who decided almost immediately
    would have a `normdecidedate` shortly after the `normofferdate`, whereas a candidate who decided on the final day
    will have a value of 1.0.

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
- `program`: a string or `Symbol` encoding the program using standard abbreviations
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
    tdecide = hasfield(typeof(applicant), :decidedate) ? normdate(applicant.decidedate, pdata) : missing
    accept = hasfield(typeof(applicant), :accept) ? applicant.accept : missing
    return NormalizedApplicant(applicant.program, season(applicant), normrank, toffer, tdecide, accept)
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
    fmatch = match_function(criteria)

Generate a matching function comparing two applicants.

    fmatch(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})

will return a number between 0 and 1, with 1 indicating a perfect match.
`template` is the applicant you wish to find a match for, and `applicant` is a candidate match.
`tnow` is used to exclude `applicant`s who had already decided by `tnow`.

The parameters of `fmatch` are determined by `criteria`:
- `criteria.matchprogram::Bool`: if `true`, only students from the same program are considered (all others return 0.0)
- `criteria.σr`: the standard deviation of `normrank` (use `Inf` if you don't want to consider rank in matches)
- `criteria.σt`: the standard deviation of `normofferdate` (use `Inf` if you don't want to consider offer date in matches)
"""
function match_function(criteria)
    return function(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})
        # Include only applicants that hadn't decided by tnow
        !ismissing(tnow) && tnow > applicant.normdecidedate && return 0.0
        # Check whether we need to match the program
        if criteria.matchprogram
            template.program !== applicant.program && return 0.0
        end
        return exp(-((template.normofferdate - applicant.normofferdate)/criteria.σt)^2/2 -
                    ((template.normrank - applicant.normrank)/criteria.σr)^2/2)
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

function run_simulation(clikelihoods::AbstractVector{<:AbstractVector{<:Real}},
                        past_applicants::AbstractVector{NormalizedApplicant},
                        nsim::Int)
    map(clikelihoods) do clike
        nsucc = 0
        for i = 1:nsim
            app = select_applicant(clike, past_applicants)
            nsucc += app.accept
        end
        nsucc/nsim
    end
end

## Lower-level utilities

# TODO: check against standard abbreviations
validateprogram(program::Symbol) = program

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

"""
    pdata = program_data(applicant, program_history)

Return data for the program and admission season matching `applicant`. One accepted format is the following:

```
program_history = Dict((year=2021, program=:NS) => (slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                       (year=2021, program=:CB) => (slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")),
)
```
"""
program_data(applicant, program_history) = program_history[program_key(applicant, program_history)]

program_key(applicant, ::Dict{K}) where K<:NamedTuple = convert(K, (year=season(applicant), program=applicant.program))

season(applicant) = year(applicant.offerdate) + (month(applicant.offerdate) > 7)
season(applicant::NormalizedApplicant) = applicant.season

end
