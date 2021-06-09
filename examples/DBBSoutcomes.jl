using AdmissionsSimulation
using AdmissionsSimulation.CSV
using AdmissionsSimulation.Measurements
using DataFrames
using Dates

progfile = "program_applicant_data.csv"
prog = DataFrame(CSV.File(progfile))
for i = 1:size(prog, 1)
    if ismissing(prog[i, "Program"])
        prog[i, "Program"] = prog[i-1, "Program"]
    end
end
progdata = Dict(ProgramKey(row."Program", row."Year") => (slots=row."Target", nmatriculants=row."Matriculants", napplicants=row."Applicants") for row in eachrow(prog))


appfile = "AcceptOffered_Hold_Outcome_w_Dates.csv"
df = DataFrame(CSV.File(appfile))

function parserow(row, program_history; warn::Bool=false)
    p = row."Program"
    ishold = !ismissing(row."Interviewed, Hold") || !ismissing(row."Interviewed, High Hold")
    da = row."Acceptance Offered"
    if !ismissing(da)
        dadmit = Date(da, dfmt)
        accept = row."Final Outcome" ∈ ("Class Member", "Deferred")
        ddecide = missing
        if accept
            dy = row."Class Member"
            ddecide = ismissing(dy) ? missing : Date(dy, dfmt)
        else
            dy = row."Declined"
            if !ismissing(dy)
                ddecide = Date(dy, dfmt)
            else
                applicant = row."Applicant"
                warn && @warn("no decision date found for $applicant")
                pd = program_history[ProgramKey(row."Program", row."Enroll Year")]
                ddecide = hasproperty(pd, :lastdecisiondate) ? pd.lastdecisiondate : missing
            end
        end
        return p, dadmit, ddecide, accept, ishold
    end
    return ishold
end

# Extract program history: the date of the first admissions offers, the date of the decision deadline
gdf = groupby(df, ["Enroll Year", "Program"])
dfmt = dateformat"mm/dd/yyyy"
program_history = Dict{ProgramKey,ProgramData}()
program_offers = Dict{ProgramKey,Tuple{Int,Int}}()   # (nadmit, nhold)
for g in gdf
    local nmatric
    dadmit, ddecide = today(), Date(0.0)  # sentinel values
    nmatric = 0
    nadmit = nhold = 0
    for row in eachrow(g)
        ret = parserow(row, progdata)
        if isa(ret, Bool)
            nhold += 1
            continue
        end
        _, thisdadmit, thisddecide, accept, ishold = ret
        dadmit = min(dadmit, thisdadmit)
        if !ismissing(thisddecide)
            ddecide = max(ddecide, thisddecide)
        end
        nmatric += accept
        nadmit += !ishold
        nhold += ishold
    end
    g1 = first(g)
    key = ProgramKey(g1."Program", g1."Enroll Year")
    pd = progdata[key]
    nmatric == pd.nmatriculants || @warn "$key claims $(pd.nmatriculants) matriculants, got $nmatric"
    program_history[key] = ProgramData(slots=pd.slots, nmatriculants=nmatric, napplicants=pd.napplicants, firstofferdate=dadmit, lastdecisiondate=ddecide)
    program_offers[key] = (nadmit, nhold)
end

# Parse each applicant
applicants = NormalizedApplicant[]
for row in eachrow(df)
    ret = parserow(row, program_history; warn=true)
    isa(ret, Bool) && continue
    progname, dadmit, ddecide, accept, ishold = ret
    key = ProgramKey(progname, dadmit)
    po = program_offers[key]
    push!(applicants, NormalizedApplicant(; program=progname, rank=(ishold ? po[1] : 1), offerdate=dadmit, decidedate=ddecide, accept=accept, program_history))
end

## Tune the matching function
lastyear = maximum(pk -> pk.season, keys(program_history))
test_applicants = filter(app->app.season == lastyear, applicants)
past_applicants = filter(app->app.season < lastyear, applicants)

# Note the more combinations, the longer it takes
σsels = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5]
σyields = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5]
σrs = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5]
σts = [0.1, 0.2, 0.5, 1.0, 2.0]
cprob = net_probability(σsels, σyields, σrs, σts; applicants=past_applicants, program_history)
idx = argmax(cprob)
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]

# Now let's re-run the most recent season using proposed strategies
offerdat = offerdata(past_applicants, program_history)
yielddat = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
progsim = cached_similarity(σsel, σyield; offerdata=offerdat, yielddata=yielddat)
fmatch = match_function(; σr, σt, progsim)
smatric = nmatric = tmatric = 0.0f0
println("Predictions based on all offers made (including wait list), from the vantage point of the beginning of the season:")
for progname in sort(collect(AdmissionsSimulation.program_abbrvs))
    global smatric, nmatric, tmatric
    papps = filter(app->app.program == progname, test_applicants)
    isempty(papps) && continue
    nmatch, smatch = 0.0f0, 0.0f0
    tnow = 0.0f0
    for app in papps
        like = match_likelihood(fmatch, past_applicants, app, tnow)
        slike = sum(like)
        iszero(slike) && continue
        nmatch += slike
        p = matriculation_probability(like, past_applicants)
        smatch += p
    end
    progkey = ProgramKey(progname, lastyear)
    pd = program_history[progkey]
    println(progname,
            ": mean # matched = ", nmatch/length(papps),
            ", target = ", pd.target_raw,
            ", estimated matriculation = ", smatch,
            ", actual matriculation = ", pd.nmatriculants)
    nmatch == 0 && continue
    smatric += smatch
    tmatric += pd.target_raw
    nmatric += pd.nmatriculants
end
println("DBBS totals: target = $tmatric, estimated = $smatric, actual = $nmatric")

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
seasonstatus = Dict{Date,Tuple{Float32,DataFrame}}()
actual_yield = Dict(map(filter(pr -> pr.first.season == lastyear, collect(program_history))) do (pk, pd)
    pk.program => pd.nmatriculants
end)
for tnow in (Date("$lastyear-03-15"), Date("$lastyear-04-01"))
    local nmatric, progdata, pnames
    nmatric, progstatus = wait_list_offers(fmatch, past_applicants, test_applicants, tnow; program_history, actual_yield)
    foffers = future_offers(test_applicants, tnow; program_history)
    pnames = sort(collect(keys(progstatus)))
    datedf = DataFrame("Program" => String[], "Target" => Int[], "Predicted" => Measurement{Float32}[], "Priority" => Float32[], "Future offers" => Int[], "Actual" => Int[], "p-value" => Float32[])
    ntarget = 0
    for pname in pnames
        status = progstatus[pname]
        progkey = ProgramKey(pname, year(tnow))
        progdata = program_history[progkey]
        push!(datedf, (pname, progdata.target_corrected, status.nmatriculants, status.priority, get(foffers, pname, 0), progdata.nmatriculants, status.poutcome))
        ntarget += progdata.target_corrected
    end
    println("\n\nOn $tnow, the target was $ntarget and the predicted inflow was $nmatric. Program-specific breakdown:")
    println(datedf)
    seasonstatus[tnow] = (nmatric, datedf)
end
