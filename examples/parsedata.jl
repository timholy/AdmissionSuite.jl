using AdmissionsSimulation
using AdmissionsSimulation.CSV
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
    # rank = ishold ? po[1] : 1
    # push!(applicants, NormalizedApplicant(; program=progname, rank, offerdate=dadmit, decidedate=ddecide, accept=accept, program_history))
    push!(applicants, NormalizedApplicant(; program=progname, offerdate=dadmit, decidedate=ddecide, accept=accept, program_history))
end

# Parse faculty data
facrecs = read_faculty_data("DBBS Formula 2021.csv")
facrecs = AdmissionsSimulation.aggregate(facrecs, AdmissionsSimulation.default_program_substitutions)
