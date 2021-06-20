using AdmissionsSimulation
using AdmissionsSimulation.Measurements
using AdmissionsSimulation.ProgressMeter
using Dates
using Statistics
using XLSX
using InvertedIndices
using DataFrames

# Load data with "parsedata.jl" before running this
# Also get the σ vectors from DBBStrain

substnan(A) = [isnan(a) ? oftype(a, -Inf) : a for a in A]

# # Since we only have a single year of data, use a LOO strategy to predict outcome
# function AdmissionsSimulation.match_correlation(σr::Real, σt::Real;
#                                           applicants,
#                                           #= fraction of other applicants that must match =# minfrac=0.01)
#     fmatch = match_function(; σr, σt)
#     nmatchs = similar(applicants, Float32)
#     pmatrics = similar(nmatchs)
#     for (i, applicant) in pairs(applicants)
#         other_applicants = applicants[Not(i)]
#         like = match_likelihood(fmatch, other_applicants, applicant, 0.0f0)
#         nmatchs[i] = sum(like)
#         sum(like) < minfrac*length(other_applicants) && return -Inf32
#         p = matriculation_probability(like, other_applicants)
#         p = clamp(p, 0.05f0, 0.95f0)
#         pmatrics[i] = p
#     end
#     return ll, nmatchs, pmatrics
# end

lastyear = maximum(pk -> pk.season, keys(program_history))
rankedapplicants = filter(app->lastyear-1 <= app.season <= lastyear, applicants)

## Collect rank info
xf2020 = XLSX.readxlsx("2019-2020-Rankings for Target formula.xlsx")
xf2021 = XLSX.readxlsx("2020-2021-Rankings for Target formula.xlsx")
prognames = sort(unique((app->app.program).(rankedapplicants)))
scores = Dict{String,Tuple{Int,Int}}()
for xf in (xf2020, xf2021)
    for prog in prognames
        prog ∈ XLSX.sheetnames(xf) || continue
        sheet = xf[prog][:]
        idxi = findnext(ismissing, sheet[:,1], 2)
        idxj = findnext(ismissing, sheet[1,:], 2)
        if idxi !== nothing && idxj !== nothing
            sheet = sheet[1:idxi-1, 2:idxj-1]
        elseif idxj !== nothing
            sheet = sheet[:, 2:idxj-1]
        elseif idxi !== nothing
            sheet = sheet[1:idxi-1, 2:end]
        else
            sheet = sheet[1:end, 2:end]
        end
        idxC = findfirst(isequal("CMTE Review Mean Score"), sheet[1,:])
        idxI = findfirst(isequal("Interview Mean Score"), sheet[1,:])
        pC = sortperm(sheet[2:end, idxC]; rev=true)
        pI = sortperm(sheet[2:end, idxI]; rev=true)
        for i = 2:size(sheet, 1)
            scores[sheet[i,1]] = (pC[i-1], pI[i-1])
        end
    end
end

scorevals = collect(values(scores))
println("Correlation between C and I rank: ", round(cor(first.(scorevals), last.(scorevals)); digits=2))

function getapps(rankidx)
    rankedapplicants = NormalizedApplicant[]
    for row in eachrow(df)
        yr = row."Enroll Year"
        lastyear - 1 <= yr <= lastyear || continue
        ret = parserow(row, program_history; warn=true)
        isa(ret, Bool) && continue
        progname, dadmit, ddecide, accept, ishold = ret
        name = row."Applicant"
        key = ProgramKey(progname, dadmit)
        pd = program_history[key]
        po = program_offers[key]
        na = NormalizedApplicant(; program=progname, rank=scores[name][rankidx], offerdate=dadmit, decidedate=ddecide, accept=accept, program_history)
        push!(rankedapplicants, na)
    end
    return rankedapplicants
end

# results = Dict{String,Tuple{Matrix{Float32}, Vector{Float32}, Vector{Bool}}}()
results = Dict{String,Array{Float32,4}}()

for (rankidx, rankcode) in ((1, "C"), (2, "I"))
    rankedapplicants = getapps(rankidx)
    corarray = match_correlation(σsels, σyields, σrs, σts;
                                 applicants=rankedapplicants, program_history)
    results[rankcode] = corarray
end

# Pick parameters
getmax(rankcode) = findmax(substnan(results[rankcode]))
(corC, idxC), (corI, idxI) = getmax("C"), getmax("I")
idx, rankcode, rankidx = corC > corI ? (idxC, "C", 1) : (idxI, "I", 2)
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]

rankedapplicants = getapps(rankidx)
test_applicants = filter(app -> app.season==lastyear, rankedapplicants)
past_applicants = filter(app -> app.season< lastyear, rankedapplicants)

offerdat = offerdata(past_applicants, program_history)
yielddat = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
progsim = cached_similarity(σsel, σyield; offerdata=offerdat, yielddata=yielddat)
fmatch = match_function(; σr, σt, progsim)
# Exercise some of the offer machinery
newoffers = Dict{Float32,Vector{Int}}()
for σthresh in (1, 2, 3)
    program_candidates = Dict{String, Vector{NormalizedApplicant}}()
    for app in test_applicants
        list = get!(Vector{NormalizedApplicant}, program_candidates, app.program)
        push!(list, app)
    end
    for (prog, list) in program_candidates
        sort!(list; by=app->app.normrank)
    end
    program_offers = initial_offers!(fmatch, program_candidates, past_applicants, Date("2021-01-01"), σthresh; program_history)
    class_size_projection = Pair{Date,Measurement{Float32}}[]
    offers = Pair{Date,Vector{String}}[]
    for d in Date("2021-01-02"):Day(1):Date("2021-04-14")
        lens = Dict(prog => length(list) for (prog, list) in program_offers)
        push!(class_size_projection, d=>add_offers!(fmatch, program_offers, program_candidates, past_applicants, d, σthresh; program_history))
        newoffers = String[]
        for (prog, list) in program_offers
            for _ = 1:length(list) -lens[prog]
                push!(newoffers, prog)
            end
        end
        push!(offers, d=>newoffers)
    end
    progoffers = Int[]
    for prog in prognames
        push!(progoffers, sum(app->app.accept, program_offers[prog]))
    end
    newoffers[σthresh] = progoffers
end
tgts, actuals = Int[], Int[]
for prog in prognames
    pd = program_history[ProgramKey(prog, 2021)]
    push!(tgts, pd.target_corrected)
    push!(actuals, pd.nmatriculants)
end
final_class = DataFrame("Program"=>prognames, "Target"=>tgts, "Actual"=>actuals, sort(["\$\\sigma_\\text{thresh}\$="*string(key)=>value for (key, value) in collect(newoffers)]; by=first)...)

include("DBBSoutcomes.jl")

# offerdat = offerdata(past_applicants, program_history)
# yielddat = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
# progsim = cached_similarity(σsel, σyield; offerdata=offerdat, yielddata=yielddat)
# fmatch = match_function(; σr, σt, progsim)

# # First, test whether the matching function produces improved outcomes
# accepts = [app.accept for app in test_applicants]
# pmatrics = map(test_applicants) do app
#     like = match_likelihood(fmatch, past_applicants, app, 0.0)
#     matriculation_probability(like, past_applicants)
# end
# cstar = cor(pmatrics, accepts)
# cshuffle = [cor(pmatrics[randperm(end)], accepts) for _ = 1:1000]
# println("% of simulations in which a particular matching function outperforms shuffled candidates:")
# println("  Full matching function vs. shuffled: $(mean(cstar .> cshuffle) * 100)%")
# fmatch_prog = match_function(; progsim)
# pmatrics_prog = map(test_applicants) do app
#     like = match_likelihood(fmatch_prog, past_applicants, app, 0.0)
#     matriculation_probability(like, past_applicants)
# end
# cstar_prog = cor(pmatrics_prog, accepts)
# println("  Matching with only program data (no individual data): $(mean(cstar_prog .> cshuffle) * 100)%")
# fmatch_ind = match_function(; σr, σt, progsim=(pa,pb)->true)
# pmatrics_ind = map(test_applicants) do app
#     like = match_likelihood(fmatch_ind, past_applicants, app, 0.0)
#     matriculation_probability(like, past_applicants)
# end
# cstar_ind = cor(pmatrics_ind, accepts)
# println("  Matching with only individual data (no program data): $(mean(cstar_ind .> cshuffle) * 100)%")
# println()

# for rankcode in ("C", "I")
#     _, pmatrics, accepts = results[rankcode]
#     rcoef = cor(pmatrics, accepts)
#     rcoefshuffles = [cor(pmatrics, accepts[randperm(end)]) for _ = 1:50000]
#     pval = mean(rcoef .<= rcoefshuffles)
#     println("Correlation for $rankcode between pmatric and accept: ", round(cor(pmatrics, accepts); digits=2), " (p=", round(pval; sigdigits=2), ")")
# end

