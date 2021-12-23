# How would 2021 have worked out if we were to:
# - eliminate faculty effort, using just the applicants
# - reserve 2 slots for PMB (Danforth agreement)
# - use a hyperbolic floor with minslots=4

if !isdefined(@__MODULE__, :pnames)
    include("parsedata.jl")
end

this_season = 2021
addprogs = Dict("PMB"=>2)              # programs that get an additive bonus
minfloor = 4

program_napplicants = Dict(pk.program=>pd.napplicants for (pk, pd) in program_history if pk.season == this_season)
nslots0 = sum(pd.target for (pk, pd) in program_history if pk.season == this_season)


# Compute the remaining slots
nslots = nslots0
for (_, n) in addprogs
    global nslots
    nslots -= n
end
# Assign slots with a floor
tgts, p = targets(program_napplicants, nothing, nslots, minfloor)
# Apply adds
for (prog, n) in addprogs
    tgts[prog] += n
end
@assert sum(values(tgts)) ≈ nslots0

dftweaks = DataFrame("" => String[], [name=>Float32[] for name in pnames]...)
push!(dftweaks, ["Tweaked"; [round(tgts[prog]; digits=1) for prog in pnames]])
push!(dftweaks, ["Actual"; [program_history[(program=prog, season=this_season)].target for prog in pnames]])

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
