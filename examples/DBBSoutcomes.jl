using AdmissionsSimulation
using CSV
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
        return p, dadmit, ddecide, accept
    end
    return nothing
end

# Extract program history: the date of the first admissions offers, the date of the decision deadline
gdf = groupby(df, ["Enroll Year", "Program"])
dfmt = dateformat"mm/dd/yyyy"
program_history = Dict{ProgramKey,ProgramData}()
for g in gdf
    dadmit, ddecide = today(), Date(0.0)  # sentinel values
    nadmit = 0
    for row in eachrow(g)
        ret = parserow(row, progdata)
        ret === nothing && continue
        _, thisdadmit, thisddecide, accept = ret
        dadmit = min(dadmit, thisdadmit)
        if !ismissing(thisddecide)
            ddecide = max(ddecide, thisddecide)
        end
        nadmit += accept
    end
    g1 = first(g)
    key = ProgramKey(g1."Program", g1."Enroll Year")
    pd = progdata[key]
    nadmit == pd.nmatriculants || @warn "$key claims $(pd.nmatriculants) matriculants, got $nadmit"
    program_history[key] = ProgramData(slots=pd.slots, nmatriculants=nadmit, napplicants=pd.napplicants, firstofferdate=dadmit, lastdecisiondate=ddecide)
end

# Parse each applicant
applicants = NormalizedApplicant[]
for row in eachrow(df)
    ret = parserow(row, program_history; warn=true)
    ret === nothing && continue
    progname, dadmit, ddecide, accept = ret
    push!(applicants, NormalizedApplicant(; program=progname, offerdate=dadmit, decidedate=ddecide, accept=accept, program_history))
end

# Program stats
offdata = AdmissionsSimulation.offerdata(applicants, program_history)
using AdmissionsSimulation: Outcome
ydata = AdmissionsSimulation.yielddata(Tuple{Outcome,Outcome,Outcome}, applicants)
progsim = AdmissionsSimulation.cached_similarity(0.3f0, 0.3f0; offerdata=offdata, yielddata=ydata)


# Tune the matching function. Here we only have program and offer date to use.
# Experimentation suggests that it's good to match the program.
lastyear = maximum(app->app.season, applicants)
past_applicants = filter(app->app.season != lastyear, applicants)
applicants = filter(app->app.season == lastyear, applicants)
function netlikelihood(σt, applicants, past_applicants; matchprogram=false)
    fmatch = match_function(;matchprogram, σt)
    l = 0.0f0
    for app in applicants
        p = matriculation_probability(match_likelihood(fmatch, past_applicants, app, 0.0f0), past_applicants)
        isnan(p) && continue
        l += app.accept ? p : -p
    end
    return l
end
σtrng = 0.1:0.1:1.5
nlk = [netlikelihood(σt, applicants, past_applicants; matchprogram=true) for σt in σtrng]
σt = σtrng[argmax(nlk)]
