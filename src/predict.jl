
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

## Model training

"""
    match_correlation(σsel::Real, σyield::Real, σr::Real, σt::Real;
                      applicants, past_applicants, offerdata, yielddata,
                      ptail=0.05, minfrac=0.01)

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
function match_correlation(σsel::Real, σyield::Real, σr::Real, σt::Real;
                           applicants, past_applicants, offerdata, yielddata,
                           ptail=0.05f0,
                           #= fraction of prior applicants that must match =# minfrac=0.01)
    progsim = cached_similarity(σsel, σyield; offerdata, yielddata)
    fmatch = match_function(; σr, σt, progsim)
    pmatrics, accepts = Float32[], Bool[]
    for applicant in applicants
        like = match_likelihood(fmatch, past_applicants, applicant, 0.0f0)
        sum(like) < minfrac*length(past_applicants) && return NaN32
        p = matriculation_probability(like, past_applicants)
        p = clamp(p, ptail, 1-ptail)
        push!(pmatrics, p)
        push!(accepts, applicant.accept)
    end
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
    yrmin, yrmax = extrema(pk->pk.season, keys(program_history))
    corarray = zeros(Float32, length(σsels), length(σyields), length(σrs), length(σts))
    progress = Progress((yrmax - yrmin)*length(σrs)*length(σts); desc="Computing accuracy vs parameters for each year (progress slows in later years): ")
    nyrs = 0
    for yr = yrmin+1:yrmax
        yrapplicants = filter(app -> app.season == yr, applicants)
        prevapplicants = filter(app -> app.season < yr, applicants)
        isempty(yrapplicants) && continue
        nyrs += 1
        od = offerdata(prevapplicants, program_history)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, prevapplicants)
        for k in eachindex(σrs), l in eachindex(σts)
            for i in eachindex(σsels), j in eachindex(σyields)
                corarray[i,j,k,l] += match_correlation(σsels[i], σyields[j], σrs[k], σts[l];
                                                       applicants=yrapplicants, past_applicants=prevapplicants,
                                                       offerdata=od, yielddata=yd, kwargs...)
            end
            ProgressMeter.next!(progress; showvalues=[(:yr, yr)])
        end
    end
    return corarray/nyrs
end
