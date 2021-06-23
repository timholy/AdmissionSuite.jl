using AdmissionsSimulation
using DataFrames

# Load the data with "parsedata.jl" before running this

# Create the table of # of applicants
yrs = 2017:2021
nappm = Vector{Union{Missing,Int}}(undef, length(yrs))
fill!(nappm, missing)
dfnapplicants = DataFrame("Year"=>yrs, (name=>copy(nappm) for name in pnames)...)
for (pk, pd) in program_history
    i = findfirst(isequal(pk.season), yrs)
    i === nothing && continue
    j = findfirst(isequal(pk.program), names(dfnapplicants))
    j === nothing && continue
    dfnapplicants[i,j] = pd.napplicants
end

#
function compute_schemes(program_data, facrecs)
    N = sum(pr->pr.second.target_corrected, program_data)  # total number of target slots across all programs
    program_napplicants = Dict(pk.program => pd.napplicants for (pk, pd) in program_data)
    program_nslots = Dict(pk.program => pd.target_corrected for (pk, pd) in program_data)
    prognames = sort(collect(keys(program_napplicants)))

    schemen = Dict{String,Int}()   # effective total number of faculty, by scheme

    # Compute affiliation-based weights
    progaffil = Dict{String,Vector{Float32}}()
    for scheme in (:primary, :all, :normalized, :weighted)
        naffil = faculty_affiliations(facrecs, scheme)
        schemen[String(scheme)] = round(Int, sum(last, naffil))
        waffil = [naffil[prog] for prog in prognames]
        waffil = waffil / sum(waffil)   # normalize across programs
        progaffil[String(scheme)] = waffil
    end

    # Effort-based weights
    sc = calibrate_service(facrecs)
    _, pnameseffort, E = faculty_effort(facrecs, 2016:2021; sc)   # FIXME
    @assert pnameseffort == prognames
    progeffort = Dict{String,Vector{Float32}}()
    for scheme in (:thresheffort, :normeffort, :effortshare)
        fiis = faculty_involvement(E; scheme)
        schemen[string(scheme)] = round(Int, sum(fiis))
        progeffort[string(scheme)] = fiis / sum(fiis)
    end

    dfweights = DataFrame("Program"=>prognames,
                          "AffilPrimary"=>progaffil["primary"],
                          "AffilAll"=>progaffil["all"],
                          "AffilNorm"=>progaffil["normalized"],
                          "AffilWeight"=>progaffil["weighted"],
                          "ThreshEffort"=>progeffort["thresheffort"],
                          "NormEffort"=>progeffort["normeffort"],
                          "EffortShare"=>progeffort["effortshare"])
    slotprs = Any["Program"=>prognames]
    for name in names(dfweights)
        name == "Program" && continue
        tgts = targets(program_napplicants, Dict(progname=>fii for (progname, fii) in zip(prognames, dfweights[!, name])), N)
        push!(slotprs, name=>[tgts[prog] for prog in prognames])
    end
    dfslots = DataFrame(slotprs)

    dfweights = permutedims(dfweights, 1, "Scheme")
    dfslots = permutedims(dfslots, 1, "Scheme")
    for j = 2:length(prognames)+1, i = 1:size(dfweights, 1)
        dfweights[i,j] = round(dfweights[i,j]; digits=2)
        dfslots[i,j] = round(dfslots[i,j]; digits=1)
    end
    push!(dfslots, ["Actual 2021", [program_nslots[prog] for prog in prognames]...])

    schemelkup = Dict(
                    "AffilPrimary"=>"primary",
                    "AffilAll"=>"all",
                    "AffilNorm"=>"normalized",
                    "AffilWeight"=>"weighted",
                    "EffortShare"=>"effortshare",
                    "ThreshEffort"=>"thresheffort",
                    "NormEffort"=>"normeffort")
    dfscheme = DataFrame("Scheme"=>dfweights.Scheme, "Num. faculty"=>[schemen[schemelkup[sch]] for sch in dfweights.Scheme])

    return dfweights, dfslots, dfscheme
end

yr = 2021
this_season = filter(pr->pr.first.season == yr, program_history)

# Compute the FIIs, slots, and effective number of total faculty for actual DBBS programs
dfweights, dfslots, dfscheme = compute_schemes(this_season, facrecs)
# Compute the FIIs, slots, and effective number of faculty under two scenarios in which some programs
# are merged into a "super-program." This is a test of invariance.
mergeresults = DataFrame("Scheme" => copy(dfslots.Scheme))
for subst in (["CSB"=>"CmteB", "DRSCB"=>"CmteB", "HSG"=>"CmteB", "MGG"=>"CmteB"],  # CommitteeB programs
              ["DRSCB"=>"B5068", "MCB"=>"B5068", "MGG"=>"B5068", "MMMP"=>"B5068"], # Require MCB course, Bio 5068
              )
    name = last(first(subst))
    AdmissionsSimulation.addprogram(name)
    try
        mergeafter = zero(dfslots[!, first(first(subst))])
        for (from, _) in subst
            mergeafter += dfslots[!, from]
        end
        mergeafter = round.(mergeafter; digits=1)

        pd = AdmissionsSimulation.aggregate(this_season, subst)
        fr = AdmissionsSimulation.aggregate(facrecs, subst)
        _, dfslotsm = compute_schemes(pd, fr)
        mergebefore = dfslotsm[!, name]

        mergeresults[!, name*"-post"] = mergeafter
        mergeresults[!, name*"-pre"] = mergebefore
        mergeresults[!, name*"-\$\\Delta\$"] = round.(mergeafter - mergebefore; digits=1)
    finally
        AdmissionsSimulation.delprogram(name)
    end
end


sc = calibrate_service(facrecs)
_, pnamesE, E = faculty_effort(facrecs, 2016:2021; sc)   # FIXME

# When using `:thresheffort`, compute the mean number of votes per faculty per program, as a function of the threshold
function votes_per_program(E, thresh)
    B = E .> thresh
    vperf = sum(B; dims=2)
    return vec(sum(B .* vperf; dims=1)./sum(B; dims=1))
end
dfvotes = DataFrame("Threshold" => Float32[], [prog => Float32[] for prog in pnames]...)
for thresh in exp.(range(log(0.1), stop=log(50), length=101))
    push!(dfvotes, [thresh; votes_per_program(E, thresh)])
end

# Analyze the impact of floors when using `:normeffort`
program_nfaculty = Dict(name => fᵢ for (name, fᵢ) in zip(pnamesE, faculty_involvement(E; scheme=:normeffort)))
program_napplicants = Dict(pk.program => pd.napplicants for (pk, pd) in this_season)
N = sum(pr->pr.second.target_corrected, this_season)
tgtsraw = targets(program_napplicants, program_nfaculty, N)
tgtsh, tgtparams = targets(program_napplicants, program_nfaculty, N, 4)                   # hyperbolic floor
tgtsl = AdmissionsSimulation.targets_linear(program_napplicants, program_nfaculty, N, 3)  # linear floor (what we did in 2021)
progs_by_size = sort(collect(tgtsraw); by=last)
Δl = [tgtsl[prog] - tgtsraw[prog] for prog in first.(progs_by_size)]
Δh = [tgtsh[prog] - tgtsraw[prog] for prog in first.(progs_by_size)]

# When using `:thresheffort`, compute the mean number of votes per faculty per program, as a function of the threshold
function votes_per_program(E, thresh)
    B = E .> thresh
    vperf = sum(B; dims=2)
    return vec(sum(B .* vperf; dims=1)./sum(B; dims=1))
end
dfvotes = DataFrame("Threshold" => Float32[], [prog => Float32[] for prog in pnames]...)
for thresh in exp.(range(log(0.1), stop=log(50), length=101))
    push!(dfvotes, [thresh; votes_per_program(E, thresh)])
end
