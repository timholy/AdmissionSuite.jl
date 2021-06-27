# How would 2021 have worked out if we were to:
# - compute faculty effort for new programs (BIDS & CB) by regression against applicants
# - reserve 2 slots for PMB (Danforth agreement)
# - use a hyperbolic floor with minslots=4

include("parsedata.jl")
using GLM

this_season = 2021
effort_end_date = Date("2021-06-23")   # date on which effort table was generated
regressprogs = ["BIDS", "CB"]    # programs that get their slots set manually
addprogs = Dict("PMB"=>2)              # programs that get an additive bonus
minfloor = 4

daterange = effort_end_date-Year(5):Day(1):effort_end_date
facs, progs, E = faculty_effort(facrecs, daterange)
fs = faculty_involvement(E)
program_nfaculty = Dict(zip(progs, fs))
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
end
# Compute the remaining slots
nslots = nslots0
for (_, n) in addprogs
    global nslots
    nslots -= n
end
# Assign slots with a floor
tgts, p = targets(program_napplicants, program_nfaculty, nslots, minfloor)
# Apply adds
for (prog, n) in addprogs
    tgts[prog] += n
end
@assert sum(values(tgts)) ≈ nslots0

dftweaks = DataFrame("" => String[], [name=>Float32[] for name in pnames]...)
push!(dftweaks, ["Tweaked"; [round(tgts[prog]; digits=1) for prog in pnames]])
push!(dftweaks, ["Actual"; [program_history[ProgramKey(prog, this_season)].target_corrected for prog in pnames]])

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
