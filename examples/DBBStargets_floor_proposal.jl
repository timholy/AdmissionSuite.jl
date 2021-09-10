# How would 2021 have worked out if we were to:
# - compute faculty effort for new programs (BIDS & CB) by regression against applicants
# - reserve 2 slots for PMB (Danforth agreement)
# - use a hyperbolic floor with minslots=4

using AdmissionsSimulation

if !isdefined(@__MODULE__, :pnames)
    include("parsedata.jl")
end
using GLM

this_season = 2021
effort_end_date = Date("2021-06-23")   # date on which effort table was generated
regressprogs = ["BIDS", "CB"]    # programs that get their slots set manually
addprogs = Dict("PMB"=>2)              # programs that get an additive bonus
minfloor = 4

daterange = effort_end_date-Year(5):Day(1):effort_end_date
facs, progs, E = faculty_effort(facrecs, daterange)
fs = faculty_involvement(E)
fst = faculty_involvement(E; scheme=:thresheffort)
program_nfaculty = Dict(zip(progs, fs))
program_nfacultyt = Dict(zip(progs, Float32.(fst)))
program_nfacultyp = faculty_affiliations(facrecs)
program_napplicants = Dict(pk.program=>pd.napplicants for (pk, pd) in program_history if pk.season == this_season)
nslots0 = sum(pd.target_corrected for (pk, pd) in program_history if pk.season == this_season)

# Perform the regression to adjust faculty effort
nf = [program_nfaculty[prog] for prog in pnames if prog ∉ regressprogs]
na = [program_napplicants[prog] for prog in pnames if prog ∉ regressprogs]
lbls = [prog for prog in pnames if prog ∉ regressprogs]
model = glm(reshape(Float32.(na), :, 1), nf, Normal(), IdentityLink())
preds = predict(model, reshape(Float32[program_napplicants[prog] for prog in regressprogs], :, 1))
for (prog, pred) in zip(regressprogs, preds)
    program_nfaculty[prog] = pred
    program_nfacultyt[prog] = pred
end
# Compute the remaining slots
nslots = nslots0
for (_, n) in addprogs
    global nslots
    nslots -= n
end
# Assign slots with a floor
tgtshf, tgtparamsf = targets(program_napplicants, program_nfaculty, nslots, minfloor)
tgtshft = AdmissionsSimulation.targets_linear(program_napplicants, program_nfacultyt, nslots, 3)
tgtmin, tgtminparams = AdmissionsSimulation.targets_min(program_napplicants, program_nfaculty, nslots, 4)
tgtsha, tgtparamsa = targets(program_napplicants, nothing, nslots, minfloor)
tgtsra = targets(program_napplicants, nothing, nslots)
# Apply adds
for (prog, n) in addprogs
    tgtshf[prog] += n
    tgtshft[prog] += n
    tgtmin[prog] += n
    tgtsha[prog] += n
    tgtsra[prog] += n
end
@assert sum(values(tgtshf)) ≈ nslots0
@assert sum(values(tgtmin)) ≈ nslots0
@assert sum(values(tgtsha)) ≈ nslots0

dftweaks = DataFrame("" => String[], [name=>Float32[] for name in pnames]...)
slots2021 = [program_history[ProgramKey(prog, this_season)].target_corrected for prog in pnames]
push!(dftweaks, ["Actual 2021"; slots2021])
push!(dftweaks, ["Intended 2021 calculation"; [round(tgtshft[prog]; digits=1) for prog in pnames]])
push!(dftweaks, ["Applicants+Faculty (norm)"; [round(tgtshf[prog]; digits=1) for prog in pnames]])
slotsrec = [round(tgtsha[prog]; digits=1) for prog in pnames]
push!(dftweaks, ["Applicants only"; slotsrec])
push!(dftweaks, ["Applicants, no baseline"; [round(tgtsra[prog]; digits=1) for prog in pnames]])

dfgradual = DataFrame("" => String[], [name=>Float32[] for name in pnames]...)
push!(dfgradual, ["2022"; round.(2*slots2021/3 + slotsrec/3; digits=1)])
push!(dfgradual, ["2023"; round.(slots2021/3 + 2*slotsrec/3; digits=1)])
push!(dfgradual, ["2024"; slotsrec])

# Comparing NS and CommitteeB
aspct(x) = round(Int, 100*x)
CmteB = ["CSB", "DRSCB", "HSG", "MGG"]

dfCmteB = DataFrame("" => String[], "NS"=>Int[], "CmteB"=>Int[])
napp = sum(last, program_napplicants)
push!(dfCmteB, ["% applicants", aspct(program_napplicants["NS"]/napp), aspct(sum(program_napplicants[prog] for prog in CmteB)/napp)])
nf = sum(last, program_nfaculty)
push!(dfCmteB, ["% faculty (norm. effort)", aspct(program_nfaculty["NS"]/nf), aspct(sum(program_nfaculty[prog] for prog in CmteB)/nf)])
nf = sum(last, program_nfacultyp)
push!(dfCmteB, ["% faculty (primary affil)", aspct(program_nfacultyp["NS"]/nf), aspct(sum(program_nfacultyp[prog] for prog in CmteB)/nf)])
# push!(dfCmteB, ["raw % slots (no baseline)", aspct(tgtsra["NS"]/nslots0), aspct(sum(tgtsra[prog] for prog in CmteB)/nslots0)])
push!(dfCmteB, ["% slots in 2021",
                aspct(program_history[ProgramKey("NS", 2021)].target_corrected/nslots0),
                aspct(sum(program_history[ProgramKey(prog, 2021)].target_corrected for prog in CmteB)/nslots0)])
nf = sum(last, program_nfacultyt)
push!(dfCmteB, ["% faculty (thresh. effort)", aspct(program_nfacultyt["NS"]/nf), aspct(sum(program_nfacultyt[prog] for prog in CmteB)/nf)])
push!(dfCmteB, ["# slots from baseline", 3, 12])
# using PyPlot: PyPlot, plt
# fig, ax = plt.subplots()
# ax.scatter(na, nf)
# for (a, f, lbl) in zip(na, nf, lbls)
#     ax.text(a, f, lbl)
# end
# xl, yl = ax.get_xlim(), ax.get_ylim()
# ax.set_xlim((0, xl[2]))
# ax.set_ylim((0, yl[2]))
# ax.set_xlabel("# applicants")
# ax.set_ylabel("# faculty (NormEffort)")
# fig.tight_layout()
# fig.savefig("applicants_faculty_regression.pdf")
