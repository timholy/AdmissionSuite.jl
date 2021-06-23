using PyPlot: PyPlot, plt
using Colors
using Distributions

# Program similarity
pnames = setdiff(sort(collect(keys(yielddat))), ["B", "CMB"])  # remove outdated programs
psim = [[progsim_pg(p1, p2) for p1 in pnames, p2 in pnames],
        [progsim(p1, p2) for p1 in pnames, p2 in pnames]]
fig, axs = plt.subplots(1, 2; figsize=(6,3))
for (i, ax) in enumerate(axs)
    ax.imshow(psim[i])
    ax.set_xticks(0:length(pnames)-1)
    ax.set_xticklabels(pnames; rotation="vertical")
    if i == 1
        ax.set_yticks(0:length(pnames)-1)
        ax.set_yticklabels(pnames)
    else
        ax.set_yticks(1:0)
    end

end
fig.tight_layout()
fig.savefig("program_similarity.pdf")

# Program comparison data
cols = hex.(distinguishable_colors(length(pnames), [colorant"white"]; dropseed=true))
fig, axs = plt.subplots(1, 2; figsize=(6,3))
ax = axs[1]
sel = [(od = offerdat[n]; od[1]/(od[1] + od[2])) for n in pnames]
ax.bar(0:length(pnames)-1, 100*sel)
ax.set_xticks(0:length(pnames)-1)
ax.set_xticklabels(pnames; rotation="vertical")
ax.set_ylabel("% admitted")
ax = axs[2]
len(::Type{NTuple{N,T}}) where {N,T} = N
accepts = zeros(len(valtype(yielddat)), length(pnames))
declines = zero(accepts)
for (j, n) in enumerate(pnames)
    yd = yielddat[n]
    for (i, o) in enumerate(yd)
        accepts[i,j] = o.naccepts
        declines[i,j] = o.ndeclines
    end
end
xc = [1/6, 3/6, 5/6]
adnorm = sum(accepts; dims=1) + sum(declines; dims=1)
lna = plt.plot(xc, 100*accepts ./ adnorm)
lnd = plt.plot(xc, 100*declines ./ adnorm, "--")
for lns in (lna, lnd)
    for (ln,col) in zip(lns, cols)
        ln.set_color("#"*lowercase(col))
    end
end
ax.set_xticks(xc)
ax.set_xticklabels(["Early", "Mid", "Late"])
ax.set_xlabel("Time")
ax.set_ylabel("% of offers")
ax.legend(lna, pnames; fontsize="x-small", bbox_to_anchor=(1,1))
fig.tight_layout()
fig.savefig("program_similarity_data.pdf")

# Distribution of outcomes from vantage point of beginning of the season
fig, ax = plt.subplots(1, 1; figsize=(5,3))
ex_wl, ex_no_wl = extrema(nmatrics_wl), extrema(nmatrics_no_wl)
nmrng = min(ex_wl[1], ex_no_wl[2]):max(ex_wl[1], ex_no_wl[2])
h1 = ax.hist(nmatrics_wl, bins=nmrng, histtype="step")
h2 = ax.hist(nmatrics_no_wl, bins=nmrng, histtype="step")
ax.set_xlabel("# of matriculants")
ax.set_ylabel("# of simulations")
ax.legend(("all offers", "exclude waitlist"); fontsize="x-small", bbox_to_anchor=(1,1))
ax.plot(nmrng, pdf.(Poisson(mean(nmatrics_wl)), nmrng) * length(nmatrics_wl), color=h1[3][1].get_edgecolor(), linestyle="dotted")
ax.plot(nmrng, pdf.(Poisson(mean(nmatrics_no_wl)), nmrng) * length(nmatrics_no_wl), color=h2[3][1].get_edgecolor(), linestyle="dotted")
fig.tight_layout()
fig.savefig("outcome_distribution.pdf")

# Waitlist dynamics
fig, axs = plt.subplots(1, 3; figsize=(7,3))
ax = axs[1]
ex = extrema(dbbsnmatric)
wlrng = ex[begin]:ex[end]
h1 = ax.hist(dbbsnmatric; bins=wlrng, histtype="step")
ax.plot(wlrng, pdf.(Poisson(mean(dbbsnmatric)), wlrng) * length(dbbsnmatric), color=h1[3][1].get_edgecolor(), linestyle="dotted")
ax.set_xlabel("# of matriculants")
ax.set_ylabel("# of simulations")
ax = axs[2]
nex = sort(collect(nexhaust))
ax.bar(0:length(nex)-1, 100*last.(nex)/length(dbbsnmatric))
ax.set_xticks(0:length(nex)-1)
ax.set_xticklabels(first.(nex); rotation="vertical")
ax.set_ylabel("% of waitlist exhaustion")
ax = axs[3]
ax.bar(0:length(dates)-1, noffers / length(dbbsnmatric))
ax.set_xticks(0:length(dates)-1)
ax.set_xticklabels(dates; rotation="vertical")
ax.set_ylabel("Mean # offers extended")
fig.tight_layout()
fig.savefig("outcome_waitlist_distribution_$rankstate.pdf")

# Faculty service (aggregate by program)
totsvc = sort(collect(AdmissionsSimulation.program_service(facrecs)); by=first)
prognames = first.(totsvc)
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

if isdefined(@__MODULE__, :class_size_projection)
    fig, ax = plt.subplots(1, 1)
    d = first.(class_size_projection)
    sz = last.(class_size_projection)
    msz, σsz = (x->x.val).(sz), (x->x.err).(sz)
    ax.errorbar(d, msz, yerr=σsz)
    ax.set_xlabel("Date")
    for lbl in ax.get_xticklabels()
        lbl.set_rotation(90)
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

    fig, ax = plt.subplots(1, 1)
    x = 0.0:0.1:maximum(last, tgtsraw)
    ax.plot(x, 3 .+ (101-39)/101 * x)
    ax.plot(x, sqrt.(16 .+ (tgtparams.N′/101)^2 * x.^2))
    ax.plot(x, x)
    ax.legend(("linear", "hyperbolic", "raw"))
    ax.set_xlabel("Slots (raw)")
    ax.set_ylabel("Slots with floor")
    fig.tight_layout()
    fig.savefig("floor_schemes.pdf")
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
