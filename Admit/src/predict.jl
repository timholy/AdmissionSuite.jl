
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
    nmatriculants = run_simulation(pmatrics::AbstractVector, nsim::Int=100)

Given a list of candidates each with probability of matriculation `pmatrics[i]`, perform `nsim` simulations of their
admission decisions and compute the total number of matriculants in each simulation.
"""
function run_simulation(pmatrics::AbstractVector{<:Real},
                        nsim::Int=100)
    function nmatric(ps)
        n = 0
        for p in ps
            n += (rand() <= p)
        end
        return n
    end
    return [nmatric(pmatrics) for i = 1:nsim]
end

priority(pred, target) = (target - pred)/sqrt(target)

"""
    nmatric, progstatus = wait_list_analysis(fmatch::Function,
                                             past_applicants::AbstractVector{NormalizedApplicant},
                                             applicants::AbstractVector{NormalizedApplicant},
                                             tnow::Date;
                                             program_history,
                                             actual_yield=nothing)

Compute the estimated number `nmatric` of matriculants and the program-specific yield prediction and wait-list priority, `progstatus`.
`progstatus` is a mapping `progname => progyp::ProgramYieldPrediction` (see [`ProgramYieldPrediction`](@ref)). `nmatric` assumes all
`applicants` get offers.

The arguments are similarly to [`match_likelihood`](@ref). If you're doing a post-hoc analysis, `actual_yield` can be a
`Dict(progname => nmatric)`, in which case the p-value for the observed outcome will also be stored in `progstatus`.
"""
function wait_list_analysis(fmatch::Function,
                            past_applicants::AbstractVector{NormalizedApplicant},
                            applicants::AbstractVector{NormalizedApplicant},
                            tnow::Union{Date,Real};
                            program_history,
                            actual_yield=nothing)
    yr = season(only(unique(season, applicants)))
    progyields = Dict{String,ProgramYieldPrediction}()
    nmatric = 0.0f0 ± 0.0f0
    for (progkey, progdata) in program_history
        progkey.season == yr || continue
        progname = progkey.program
        ntnow = isa(tnow, Date) ? normdate(tnow, progdata) : tnow
        # Select applicants to this program who already have an offer
        papplicants = filter(app -> app.program == progname && (app.normofferdate < ntnow || iszero(app.normofferdate)), applicants)
        ppmatrics = map(papplicants) do applicant
            if !ismissing(applicant.normdecidedate)
                applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
            end
            like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
            return matriculation_probability(like, past_applicants)
        end
        pnmatric = sum(ppmatrics)
        simnmatric = run_simulation(ppmatrics, 10^4)
        estmatric = round(mean(simnmatric); digits=1) ± round(std(simnmatric); digits=1)
        progtarget = progdata.target_corrected
        poutcome = missing
        if actual_yield !== nothing
            wlapplicants = filter(app -> app.program == progname && (app.normofferdate >= ntnow && !iszero(app.normofferdate)), applicants)
            for applicant in wlapplicants
                like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
                push!(ppmatrics, matriculation_probability(like, past_applicants))
            end
            wlnmatric = sum(ppmatrics)
            simnmatric = run_simulation(ppmatrics, 10^4)
            yld = actual_yield[progname]
            Δyld = abs(yld - wlnmatric)
            poutcome = sum(abs.(simnmatric .- wlnmatric) .>= Δyld)/length(simnmatric)
        end
        progyields[progname] = ProgramYieldPrediction(estmatric, priority(pnmatric, progtarget), poutcome)
        nmatric += estmatric
    end
    return nmatric, progyields
end

"""
    nmatric, pq0=>pq = add_offers!(fmatch, program_offers::Dict, program_candidates::Dict, past_applicants, tnow::Date=today(), σthresh=2; program_history)

Transfer applicants from `program_candidates` to `program_offers` depending on whether projections in `nmatric` are below DBBS-wide
target by at least `σthresh` standard deviations.  `nmatric0` is computed upon entrance, while `nmatric` reflects updated projections after
adding offers. Likewise `pq0` is the program-priority initially, and `pq` after adding offers.

`tnow` should be the date for which the computation should be performed, and is used to determine whether candidates
have already informed us of their decision.

Programs are prioritized for offers by the deficit divided by the expected noise.
"""
function add_offers!(fmatch::Function,
                     program_offers::Dict{String,<:AbstractVector{NormalizedApplicant}},
                     program_candidates::Dict{String,<:AbstractVector{NormalizedApplicant}},
                     past_applicants::AbstractVector{NormalizedApplicant},
                     tnow::Date=today(),
                     σthresh::Real=2;
                     target::Union{Int,Nothing}=nothing,
                     program_history)
    function calc_pmatric(applicant, pd = program_history[ProgramKey(applicant)])
        ntnow = normdate(tnow, pd)
        applicant.normdecidedate !== missing && applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
        like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
        return matriculation_probability(like, past_applicants)
    end
    pq = PriorityQueue{String,Float32}(Base.Order.Reverse)
    # Compute the total target
    _season = season(tnow)
    if target === nothing
        target = compute_target(program_history, _season)
    end
    # Estimate our current class size
    ppmatrics = Dict{String,Vector{Float32}}()
    allpmatrics = Float32[]
    for (program, list) in program_offers
        pd = program_history[ProgramKey(program, _season)]
        pmatrics = calc_pmatric.(list, (pd,))
        ppmatrics[program] = pmatrics
        append!(allpmatrics, pmatrics)
    end
    nmatrics = run_simulation(allpmatrics, 1000)
    nmatric0 = nmatric = mean(nmatrics) ± std(nmatrics)
    nmatric.val + σthresh * nmatric.err > target && return nmatric=>nmatric, pq=>copy(pq)
    # Iteratively add candidates by program-priority
    for (program, pmatrics) in ppmatrics
        pd = program_history[ProgramKey(program, _season)]
        tgt = pd.target_corrected
        tgt == 0 && continue
        pq[program] = priority(sum(pmatrics), tgt)
    end
    pq0 = copy(pq)
    while !isempty(pq)
        program, p = dequeue_pair!(pq)
        p < zero(p) && continue
        candidates = program_candidates[program]
        isempty(candidates) && continue
        applicant = popfirst!(candidates)
        push!(program_offers[program], applicant)
        pmatric = calc_pmatric(applicant)
        pmatrics = ppmatrics[program]
        push!(pmatrics, pmatric)
        push!(allpmatrics, pmatric)
        pd = program_history[ProgramKey(program, _season)]
        tgt = pd.target_corrected
        pq[program] = priority(sum(pmatrics), tgt)
        nmatrics = run_simulation(allpmatrics, 1000)
        nmatric = mean(nmatrics) ± std(nmatrics)
        nmatric.val + σthresh * nmatric.err > target && break
    end
    return nmatric0 => nmatric, pq0 => pq
end

"""
    program_offers = initial_offers!(fmatch, program_candidates::Dict, past_applicants, tnow::Date=today(), σthresh=2; program_history)

Allocate initial offers of admission at the beginning of the season.  See [`add_offers!`](@ref) for more information.
See also [`generate_fake_candidates`](@ref) to plan offers in cases where some programs want to make their initial offers
before other programs have finished interviewing.
"""
function initial_offers!(fmatch::Function, program_candidates::Dict, args...; kwargs...)
    program_offers = Dict(program => NormalizedApplicant[] for program in keys(program_candidates))
    add_offers!(fmatch, program_offers, program_candidates, args...; kwargs...)
    return program_offers
end

## Model training

function collect_predictions!(fmatch::Function, pmatrics::AbstractVector, accepts::AbstractVector{Bool};
                              applicants, past_applicants,
                              ptail=0.0f0,
                              #= fraction of prior applicants that must match =# minfrac=0.01)
    nviolations = 0
    for applicant in applicants
        like = match_likelihood(fmatch, past_applicants, applicant, 0.0f0)
        nviolations += sum(like) < minfrac*length(past_applicants)
        p = matriculation_probability(like, past_applicants)
        p = clamp(p, ptail, 1-ptail)
        push!(pmatrics, p)
        push!(accepts, applicant.accept)
    end
    return nviolations
end

"""
    match_correlation(fmatch; applicants, past_applicants, ptail=0.0f0, minfrac=0.01)

Compute the correlation between estimated matriculation probability and decline/accept
for a list of `applicants`' matriculation decisions.
This function is used to evaluate the accuracy of predictions made by specific model parameters.

`fmatch(reference, applicant, tnow)` is the similarity-computation function.
`ptail` is used to clamp the estimated matriculation probability between bounds, `clamp(pmatric, ptail, 1-ptail)`.
`minfrac` expresses the minimum fraction of `past_applicants`
allowed to be matched; any `test_applicant` matching fewer than these (in the sense of the
sum of likelihoods computed by [`match_likelihood`](@ref)) leads to a return value of `NaN`.
"""
function match_correlation(fmatch::Function; kwargs...)
    pmatrics, accepts = Float32[], Bool[]
    iszero(collect_predictions!(fmatch, pmatrics, accepts; kwargs...)) || return NaN32
    c = cor(pmatrics, accepts)
    return isnan(c) ? 0.0f0 : c
end

match_correlation(σsel::Real, σyield::Real, σr::Real, σt::Real; offerdata, yielddata, kwargs...) =
    match_correlation(fmatch_prog_rank_date(σsel, σyield, σr, σt; offerdata, yielddata); kwargs...)

"""
    match_correlation(matchcreator::Function, σlists::AbstractVector...;
                      applicants, program_history, kwargs...)

Compute the prediction accuracy using historical data. For each year in `program_history` other than the earliest,
use prior data to predict the probability of matriculation for each applicant.

The `σ` lists contain the values that will be used to compute accuracy; the return value is an n-dimensional array evaluating
the correlation between estimated matriculation probability and acceptance for all possible combinations of these parameters.
`matchcreator(σ1, σ2...; offerdata, yielddata)` should return a similarity-computing function `fmatch(template, applicant, tnow)`
using the specific `σ`s provided.

Tuning essentially corresponds to picking the index of the entry of the return value and then setting each parameter accordingly:

```julia
corarray = match_correlation(Admit.fmatch_prog_rank_date, σsels, σyields, σrs, σts; applicants, program_history)
idx = argmax(corarray)
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]
```

`fmatch_prog_rank_date` is a default and can be omitted if you want to use this function.
"""
function match_correlation(matchcreator::Function, σlists::AbstractVector...;
                           applicants, program_history, kwargs...)
    yrmin, yrmax = extrema(app->app.season, applicants)
    corarray = zeros(Float32, map(eachindex, σlists))
    yeardata = map(yrmin+1:yrmax) do yr
        yrapplicants = filter(app -> app.season == yr, applicants)
        prevapplicants = filter(app -> app.season < yr, applicants)
        od = offerdata(prevapplicants, program_history)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, prevapplicants)
        return (yrapplicants, prevapplicants, od, yd)
    end
    pmatrics, accepts = Float32[], Bool[]
    IR = CartesianIndices(map(eachindex, σlists))
    @showprogress 1 "Computing accuracy vs parameters: " for (I, σs) in zip(IR, Iterators.product(σlists...))
        empty!(pmatrics)
        empty!(accepts)
        nbad = 0
        for yeardat in yeardata
            yrapplicants, prevapplicants, od, yd = yeardat
            fmatch = matchcreator(σs...; offerdata=od, yielddata=yd)
            nbad += collect_predictions!(fmatch, pmatrics, accepts;
                                         applicants=yrapplicants, past_applicants=prevapplicants,
                                         kwargs...)
        end
        c = cor(pmatrics, accepts)
        corarray[I] = iszero(nbad) ? (isnan(c) ? 0.0f0 : c) : NaN32
    end
    return corarray
end
function match_correlation(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;
                           kwargs...)
    return match_correlation(fmatch_prog_rank_date, σsels, σyields, σrs, σts; kwargs...)
end
