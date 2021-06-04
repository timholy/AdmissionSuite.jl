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
progdata = Dict(ProgramKey(row."Program", row."Year") => (slots=row."Target", napplicants=row."Applicants") for row in eachrow(prog))


appfile = "AcceptOffered_Hold_Outcome_w_Dates.csv"
df = DataFrame(CSV.File(appfile))

# Extract program history: the date of the first admissions offers, the date of the decision deadline
gdf = groupby(df, ["Enroll Year", "Program"])
dfmt = dateformat"mm/dd/yyyy"
program_history = Dict{ProgramKey,ProgramData}()
for g in gdf
    dadmit, ddecide = Date(now()), Date(0.0)  # sentinel values
    for row in eachrow(g)
        da = row."Acceptance Offered"
        if !ismissing(da)
            dadmit = min(dadmit, Date(da, dfmt))
            dy = row."Class Member"
            if !ismissing(dy)
                ddecide = max(ddecide, Date(dy, dfmt))
            else
                dy = row."Declined"
                if !ismissing(dy)
                    ddecide = max(ddecide, Date(dy, dfmt))
                end
            end
        end
    end
    g1 = first(g)
    key = ProgramKey(g1."Program", g1."Enroll Year")
    pd = progdata[key]
    program_history[key] = ProgramData(slots=pd.slots, napplicants=pd.napplicants, firstofferdate=dadmit, lastdecisiondate=ddecide)
end

# Parse each applicant
applicants = NormalizedApplicant[]
for row in eachrow(df)
    p = row."Program"
    da = row."Acceptance Offered"
    if !ismissing(da)
        dadmit = Date(da, dfmt)
        accept = ddecide = missing
        dy = row."Class Member"
        if !ismissing(dy)
            ddecide = Date(dy, dfmt)
            accept = true
        else
            dy = row."Declined"
            if !ismissing(dy)
                ddecide = Date(dy, dfmt)
                accept = false
            else
                applicant = row."Applicant"
                @warn("no decision date found for $applicant")
                ddecide = program_history[ProgramKey(row."Program", row."Enroll Year")].lastdecisiondate
                accept = row."Final Outcome" == "Class Member"
            end
        end
        push!(applicants, NormalizedApplicant((program=p, rank=missing, offerdate=dadmit, decidedate=ddecide, accept=accept); program_history))
    end
end

# Tune the matching function. Here we only have program and offer date to use.
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
