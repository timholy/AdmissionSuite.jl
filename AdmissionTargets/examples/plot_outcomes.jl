using PyPlot: PyPlot, plt
using Colors
using MultivariateStats

# Faculty service (aggregate by program)
totsvc = sort(collect(AdmissionTargets.program_service(facrecs)); by=first)
prognames = first.(totsvc)
programcolors = hex.(distinguishable_colors(length(prognames), [colorant"white"]; dropseed=true))
ninterviews = map(pr->pr.second.ninterviews, totsvc)
ncommittees = map(pr->pr.second.ncommittees, totsvc)
fig, ax = plt.subplots(1, 1; figsize=(3,3))
ax.scatter(ninterviews, ncommittees)
for i = 1:length(prognames)
    ax.annotate(prognames[i], (ninterviews[i], ncommittees[i]))
end
ax.set_xlabel("# interviews")
ax.set_ylabel("# thesis committees")
fig.tight_layout()
fig.savefig("faculty_service.pdf")

# Comparison of schemes
if isdefined(@__MODULE__, :dfweights)
    schemedata = Matrix(dfweights[:,begin+1:end])'
    projinfo = fit(PCA, schemedata)
    proj = MultivariateStats.transform(projinfo, schemedata)

    colorscheme = Dict("AffilPrimary"=>RGB(0.2,1,0), "AffilAll"=>RGB(1, 0, 0.8), "AffilNorm"=>RGB(0, 0.5, 0),
                       "AffilWeight"=>RGB(0, 0.6, 0), "ThreshEffort"=>RGB(0.8, 0, 1), "NormEffort"=>RGB(0,1,0),
                       "EffortShare"=>RGB(0,0.7,0.5))
    fig, ax = plt.subplots(1, 1)
    pts = ax.scatter(proj[1,:], proj[2,:], c = ("#",) .* lowercase.(hex.([colorscheme[scheme] for scheme in dfweights.Scheme])))
    for i in axes(proj, 2)
        ax.text(proj[1:2,i]..., dfweights.Scheme[i])
    end
    ax.set_aspect("equal")
    ax.set_xlabel("PC1")
    ax.set_ylabel("PC2")
    fig.tight_layout()
    fig.savefig("scheme_PCA.pdf")
end

# Impact of floors on targets
if isdefined(@__MODULE__, :Δl)
    fig, ax = plt.subplots(1, 1)
    y = 1:length(progs_by_size)
    ax.barh(y, Δl)
    ax.set_yticks(y)
    ax.set_yticklabels(first.(progs_by_size))
    ax.set_xlabel("# slots granted")
    fig.tight_layout()
    fig.savefig("linear_floors.pdf")

    fig, ax = plt.subplots(1, 1)
    y = 1:length(progs_by_size)
    ax.barh(y .+ 1/6, Δl, 1/3)
    ax.barh(y .- 1/6, Δh, 1/3)
    ax.set_yticks(y)
    ax.set_yticklabels(first.(progs_by_size))
    ax.set_xlabel("# slots granted")
    ax.legend(("linear", "hyperbolic"))
    fig.tight_layout()
    fig.savefig("linear_hyperbolic_floors.pdf")
end

# Linear vs hyperbolic floors, raw scheme
if isdefined(@__MODULE__, :nslots0)
    fig, ax = plt.subplots(1, 1, figsize=(3,3))
    x = 0.0:0.1:maximum(last, tgtsra)
    ax.plot(x, 3 .+ (nslots0-39)/nslots0 * x, color="blue")
    ax.plot(x, x, "k--")
    ax.legend(("linear", "raw"))
    ax.set_xlabel("Slots (raw)")
    ax.set_ylabel("Slots with baseline")
    fig.tight_layout()
    fig.savefig("floor_linear.pdf")

    fig, ax = plt.subplots(1, 1, figsize=(3,3))
    ax.plot(x, sqrt.(tgtparamsa.n0^2 .+ (tgtparamsa.N′/nslots0)^2 * x.^2), color="orange")
    ax.plot(x, max.(tgtminparams.minslots, (nslots0-tgtminparams.Nsave)/nslots0 .* x), color="green")
    ax.plot(x, x, "k--")
    ax.legend(("hyperbolic", "min", "raw"))
    ax.set_xlabel("Slots (raw)")
    ax.set_ylabel("Slots with baseline")
    fig.tight_layout()
    fig.savefig("floor_hyperbolic.pdf")
end

# Votes per faculty
if isdefined(@__MODULE__, :dfvotes)
    fig, ax = plt.subplots(1, 1)
    x = dfvotes.Threshold
    for (pname, color) in zip(pnames, programcolors)
        ax.semilogx(x, dfvotes[!, pname], color="#"*lowercase(color))
    end
    ax.legend(pnames; fontsize="x-small")
    ax.set_xlabel("Threshold (hrs/year)")
    ax.set_ylabel("Mean # votes/qualifying faculty")
    ax.set_ylim(0, 5)
    fig.tight_layout()
    fig.savefig("votes_per_program.pdf")
end
