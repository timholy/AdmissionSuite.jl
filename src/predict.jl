
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
`progstatus` is a mapping `progname => progyp::ProgramYieldPrediction` (see [`ProgramYieldPrediction`](@ref)).

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
            applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
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
    nmatric = add_offers!(fmatch, program_offers::Dict, program_candidates::Dict, past_applicants, tnow::Date=today(), σthresh=2; program_history)

Transfer applicants from `program_candidates` to `program_offers` depending on whether projections in `nmatric` are below DBBS-wide
target by at least `σthresh` standard deviations.  `nmatric` is computed upon entrance, and does not reflect updated projections after
adding offers. `tnow` should be the date for which the computation should be performed, and is used to determine whether candidates
have already informed us of their decision.

Programs are prioritized for offers by the deficit divided by the expected noise.
"""
function add_offers!(fmatch::Function,
                     program_offers::Dict{String,<:AbstractVector{NormalizedApplicant}},
                     program_candidates::Dict{String,<:AbstractVector{NormalizedApplicant}},
                     past_applicants::AbstractVector{NormalizedApplicant},
                     tnow::Date=today(),
                     σthresh::Real=2;
                     program_history)
    function calc_pmatric(applicant, pd = program_history[ProgramKey(applicant)])
        ntnow = normdate(tnow, pd)
        applicant.normdecidedate !== missing && applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
        like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
        return matriculation_probability(like, past_applicants)
    end
    # Compute the total target
    season = year(tnow)
    target = 0
    for program in keys(program_candidates)
        target += program_history[ProgramKey(program, season)].target_corrected
    end
    # Estimate our current class size
    ppmatrics = Dict{String,Vector{Float32}}()
    allpmatrics = Float32[]
    for (program, list) in program_offers
        pd = program_history[ProgramKey(program, season)]
        pmatrics = calc_pmatric.(list, (pd,))
        ppmatrics[program] = pmatrics
        append!(allpmatrics, pmatrics)
    end
    nmatrics = run_simulation(allpmatrics, 1000)
    nmatric = mean(nmatrics) ± std(nmatrics)
    nmatric.val + σthresh * nmatric.err > target && return nmatric
    # Iteratively add candidates by program-priority
    pq = PriorityQueue{String,Float32}(Base.Order.Reverse)
    for (program, pmatrics) in ppmatrics
        pd = program_history[ProgramKey(program, season)]
        tgt = pd.target_corrected
        tgt == 0 && continue
        pq[program] = priority(sum(pmatrics), tgt)
    end
    while true
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
        pd = program_history[ProgramKey(program, season)]
        tgt = pd.target_corrected
        pq[program] = priority(sum(pmatrics), tgt)
        nmatrics = run_simulation(allpmatrics, 1000)
        mean(nmatrics) + σthresh * std(nmatrics) > target && break
    end
    return nmatric
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

function collect_predictions!(pmatrics::AbstractVector, accepts::AbstractVector{Bool},
                              σsel::Real, σyield::Real, σr::Real, σt::Real;
                              applicants, past_applicants, offerdata, yielddata,
                              ptail=0.0f0,
                              #= fraction of prior applicants that must match =# minfrac=0.01)
    progsim = cached_similarity(σsel, σyield; offerdata, yielddata)
    fmatch = match_function(; σr, σt, progsim)
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
    match_correlation(σsel::Real, σyield::Real, σr::Real, σt::Real;
                      applicants, past_applicants, offerdata, yielddata,
                      ptail=0.0f0, minfrac=0.01)

Compute the correlation between estimated matriculation probability and decline/accept
for a list of `applicants`' matriculation decisions.
This function is used to evaluate the accuracy of predictions made by specific model parameters.

The `σ` arguments are matching parameters, see [`program_similarity`](@ref) and
[`match_function`](@ref). [`offerdata`](@ref) and [`yielddata`](@ref) are computed
by functions of the same name. `ptail` is used to clamp the estimated matriculation probability
between bounds, `clamp(pmatric, ptail, 1-ptail)`.
`minfrac` expresses the minimum fraction of `past_applicants`
allowed to be matched; any `test_applicant` matching fewer than these (in the sense of the
sum of likelihoods computed by [`match_likelihood`](@ref)) leads to a return value of `NaN`.
"""
function match_correlation(σsel::Real, σyield::Real, σr::Real, σt::Real; kwargs...)
    pmatrics, accepts = Float32[], Bool[]
    iszero(collect_predictions!(pmatrics, accepts, σsel, σyield, σr, σt; kwargs...)) || return NaN32
    c = cor(pmatrics, accepts)
    return isnan(c) ? 0.0f0 : c
end

"""
    match_correlation(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;
                      applicants, program_history, kwargs...)

Compute the prediction accuracy using historical data. For each year in `program_history` other than the earliest,
use prior data to predict the probability of matriculation for each applicant.

The `σ` lists contain the values that will be used to compute accuracy; the return value is a 4-dimensional array evaluating
the correlation between estimated matriculation probability and acceptance for all possible combinations of these parameters.
`σsel` and `σyield` will be used by [`cached_similarity`](@ref) to determine program similarity;
`σr` and `σs` will be used to measure applicant similarity.

Tuning essentially corresponds to picking the index of the entry of the return value and then setting each parameter accordingly:

```julia
corarray = match_correlation(σsels, σyields, σrs, σts; applicants, program_history)
idx = argmax(corarray)
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]
```
"""
function match_correlation(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;
                           applicants, program_history, kwargs...)
    yrmin, yrmax = extrema(app->app.season, applicants)
    corarray = zeros(Float32, length(σsels), length(σyields), length(σrs), length(σts))
    yeardata = map(yrmin+1:yrmax) do yr
        yrapplicants = filter(app -> app.season == yr, applicants)
        prevapplicants = filter(app -> app.season < yr, applicants)
        od = offerdata(prevapplicants, program_history)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, prevapplicants)
        return (yrapplicants, prevapplicants, od, yd)
    end
    @showprogress "Computing accuracy vs parameters" for k in eachindex(σrs), l in eachindex(σts)
        σr, σt = σrs[k], σts[l]
        for i in eachindex(σsels), j in eachindex(σyields)
            σsel, σyield,  = σsels[i], σyields[j]
            pmatrics, accepts = Float32[], Bool[]
            nbad = 0
            for (yr, yeardat) in zip(yrmin+1:yrmax, yeardata)
                yrapplicants, prevapplicants, od, yd = yeardat
                nbad += collect_predictions!(pmatrics, accepts, σsel, σyield, σr, σt;
                                             applicants=yrapplicants, past_applicants=prevapplicants,
                                             offerdata=od, yielddata=yd, kwargs...)
            end
            c = cor(pmatrics, accepts)
            corarray[i, j, k, l] = iszero(nbad) ? (isnan(c) ? 0.0f0 : c) : NaN32
        end
    end
    return corarray
end