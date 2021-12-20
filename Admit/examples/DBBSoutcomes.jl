using Admit
using Admit.Measurements
using Admit.ProgressMeter
using Dates
using Statistics

# include("parsedata.jl")
# include("DBBStrain.jl")

# Now let's re-run the most recent season using proposed strategies
offerdat = offerdata(past_applicants, program_history)
yielddat = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
progsim = cached_similarity(σsel, σyield; offerdata=offerdat, yielddata=yielddat)
fmatch = match_function(; σr, σt, progsim)
progsim_pg = cached_similarity(σsel_pg, σyield_pg; offerdata=offerdat, yielddata=yielddat)
fmatch_pg = match_function(; progsim=progsim_pg)

# First, test whether the matching function produces improved outcomes
accepts = [app.accept for app in test_applicants]
pmatrics = map(test_applicants) do app
    like = match_likelihood(fmatch, past_applicants, app, 0.0)
    matriculation_probability(like, past_applicants)
end
cstar = cor(pmatrics, accepts)
cshuffle = [cor(pmatrics[randperm(end)], accepts) for _ = 1:1000]
println("% of simulations in which a particular matching function outperforms shuffled candidates:")
println("  Full matching function vs. shuffled: $(mean(cstar .> cshuffle) * 100)%")
fmatch_prog = match_function(; progsim)
pmatrics_prog = map(test_applicants) do app
    like = match_likelihood(fmatch_prog, past_applicants, app, 0.0)
    matriculation_probability(like, past_applicants)
end
cstar_prog = cor(pmatrics_prog, accepts)
println("  Matching with only chosen program data (no individual data): $(mean(cstar_prog .> cshuffle) * 100)%")
pmatrics_pg = map(test_applicants) do app
    like = match_likelihood(fmatch_pg, past_applicants, app, 0.0)
    matriculation_probability(like, past_applicants)
end
cstar_pg = cor(pmatrics_pg, accepts)
println("  Matching with only trained program data (no individual data): $(mean(cstar_pg .> cshuffle) * 100)%")
fmatch_ind = match_function(; σr, σt, progsim=(pa,pb)->true)
pmatrics_ind = map(test_applicants) do app
    like = match_likelihood(fmatch_ind, past_applicants, app, 0.0)
    matriculation_probability(like, past_applicants)
end
cstar_ind = cor(pmatrics_ind, accepts)
println("  Matching with only individual data (no program data): $(mean(cstar_ind .> cshuffle) * 100)%")
println()

# Next, analyze the admission season
round1(x) = round(x; digits=1)
nmatric = tmatric = 0
smatric = 0.0f0 ± 0.0f0
tnow = 0.0f0
startdf = DataFrame("Program" => String[], "Average \\# matched/app" => Float32[], "Target" => Int[], "Predicted" => Measurement{Float32}[], "Actual" => Int[])
for progname in sort(collect(Admit.program_abbreviations))
    global smatric, nmatric, tmatric
    papps = filter(app->app.program == progname, test_applicants)
    isempty(papps) && continue
    nmatch = 0.0f0
    ppmatrics = map(papps) do app
        like = match_likelihood(fmatch, past_applicants, app, tnow)
        slike = sum(like)
        nmatch += slike
        matriculation_probability(like, past_applicants)
    end
    pnmatrics = run_simulation(ppmatrics)
    smatch = round1(mean(pnmatrics)) ± round1(std(pnmatrics))
    progkey = ProgramKey(progname, lastyear)
    pd = program_history[progkey]
    push!(startdf, (progname, round1(nmatch/length(papps)), pd.target_corrected, smatch, pd.nmatriculants))
    # println(progname,
    #         ": mean # matched = ", nmatch/length(papps),
    #         ", target = ", pd.target_raw,
    #         ", estimated matriculation = ", smatch,
    #         ", actual matriculation = ", pd.nmatriculants)
    nmatch == 0 && continue
    smatric += smatch
    tmatric += pd.target_corrected
    nmatric += pd.nmatriculants
end
println("Predictions based on all offers made (including wait list), from the vantage point of the beginning of the season:")
println(startdf)
println("DBBS totals: target = $tmatric, estimated = $smatric, actual = $nmatric")
# Simulate outcomes with and without wait list offers
nmatrics_wl = run_simulation(pmatrics, 10^4)
pmatrics_no_wl = copy(pmatrics)
for i in eachindex(test_applicants, pmatrics_no_wl)
    app = test_applicants[i]
    if app.normofferdate > normdate(Date("2021-03-15"), program_history[ProgramKey(app)])
        pmatrics_no_wl[i] = 0
    end
end
nmatrics_no_wl = run_simulation(pmatrics_no_wl, 10^4)

# Wait list analysis
function future_offers(applicants, tnow::Date; program_history)
    offers = Dict{String,Int}()
    for applicant in applicants
        pk = ProgramKey(applicant)
        ntnow = normdate(tnow, program_history[pk])
        if applicant.normofferdate >= ntnow
            key = pk.program
            offers[key] = get(offers, key, 0) + 1
        end
    end
    return offers
end
seasonstatus = Dict{Date,Tuple{Measurement{Float32},DataFrame}}()
actual_yield = Dict(map(filter(pr -> pr.first.season == lastyear, collect(program_history))) do (pk, pd)
    pk.program => pd.nmatriculants
end)
for tnow in (Date("$lastyear-03-15"), Date("$lastyear-04-01"))
    local nmatric, progdata, pnames, ntarget, progstatus
    nmatric, progstatus = wait_list_analysis(fmatch, past_applicants, test_applicants, tnow; program_history, actual_yield)
    foffers = future_offers(test_applicants, tnow; program_history)
    pnames = sort(collect(keys(progstatus)))
    datedf = DataFrame("Program" => String[], "Target" => Int[], "Predicted" => Measurement{Float32}[], "Priority" => Float32[], "Future offers" => Int[], "Actual" => Int[], "p-value" => Float32[])
    ntarget = 0
    for pname in pnames
        status = progstatus[pname]
        progkey = ProgramKey(pname, Admit.season(tnow))
        progdata = program_history[progkey]
        push!(datedf, (pname, progdata.target_corrected, status.nmatriculants, round(status.priority; digits=2), get(foffers, pname, 0), progdata.nmatriculants, status.poutcome))
        ntarget += progdata.target_corrected
    end
    println("\n\nOn $tnow, the target was $ntarget and the predicted inflow was $nmatric. Program-specific breakdown:")
    println(datedf)
    seasonstatus[tnow] = (nmatric, datedf)
end

# Run a fake admissions season, in which the code manages the offers and waitlist

function random_applicants(applicants, past_applicants; pval=0.8)
    pd = program_history[ProgramKey(first(applicants))]
    target = pd.target_corrected
    selected = eltype(applicants)[]
    waiting = similar(selected)
    pmatrics = Float32[]
    perm = randperm(length(applicants))
    i = firstindex(perm)
    while i <= lastindex(perm)
        idx = perm[i]
        app = applicants[idx]
        newapp = NormalizedApplicant(PersonalData(), app.program, app.season, app.normrank, 0.0f0, app.normdecidedate, app.accept)
        like = match_likelihood(fmatch, past_applicants, newapp, 0.0f0)
        pmatric = matriculation_probability(like, past_applicants)
        push!(selected, newapp)
        push!(pmatrics, pmatric)
        nmatrics = run_simulation(pmatrics, 1000)
        sum(nmatrics .<= target) < pval*length(nmatrics) && break
        i += 1
    end
    while i <= lastindex(perm)
        push!(waiting, applicants[perm[i]])
        i += 1
    end
    return selected, waiting
end

nsim = 1000
ntarget = 101
pval = 0.8
dates = [Date("2021-03-01"), Date("2021-03-15"), Date("2021-04-01")]
dbbsnmatric = Int[]
noffers = zeros(Int, axes(dates))
progapps = Dict{String,Vector{NormalizedApplicant}}()
for app in test_applicants
    list = get!(Vector{NormalizedApplicant}, progapps, app.program)
    push!(list, app)
end
nexhaust = Dict(k => 0 for (k, _) in progapps)
@showprogress "Simulating wait-list management" for _ = 1:nsim
    simapplicants = NormalizedApplicant[]
    waitapplicants = empty(progapps)
    for (progname, applist) in progapps
        selected, waiting = random_applicants(applist, past_applicants; pval)
        append!(simapplicants, selected)
        waitapplicants[progname] = waiting
    end
    isexhaust = Dict(k => false for (k, _) in nexhaust)
    for i in eachindex(dates)
        date = dates[i]
        while true
            local progstatus
            nmatrics, progstatus = wait_list_analysis(fmatch, past_applicants, simapplicants, date; program_history)
            nmatrics.val + nmatrics.err < ntarget || break
            # Make another offer
            priorities = sort([name => status.priority for (name, status) in progstatus]; by=last)
            while (progname = priorities[end].first; isempty(waitapplicants[progname]))
                isexhaust[progname] = true
                pop!(priorities)
            end
            waitlist = waitapplicants[priorities[end].first]
            push!(simapplicants, pop!(waitlist))
            noffers[i] += 1
        end
    end
    for (progname, isex) in isexhaust
        nexhaust[progname] += isex
    end
    push!(dbbsnmatric, sum(app->app.accept, simapplicants))
end
