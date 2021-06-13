using PyPlot: PyPlot, plt
using Colors

fig, ax = plt.subplots(1, 1; figsize=(5,3))
ex_wl, ex_no_wl = extrema(nmatrics_wl), extrema(nmatrics_no_wl)
nmrng = min(ex_wl[1], ex_no_wl[2]):max(ex_wl[1], ex_no_wl[2])
ax.hist(nmatrics_wl, bins=nmrng, histtype="step")
ax.hist(nmatrics_no_wl, bins=nmrng, histtype="step")
ax.set_xlabel("# of matriculants")
ax.set_ylabel("# of simulations")
ax.legend(("all offers", "exclude waitlist"); fontsize="x-small", bbox_to_anchor=(1,1))
fig.tight_layout()
fig.savefig("outcome_distribution.pdf")

pnames = setdiff(sort(collect(keys(yielddat))), ["B", "CMB"])  # remove outdated programs
psim = [progsim(p1, p2) for p1 in pnames, p2 in pnames]
fig, ax = plt.subplots(1, 1; figsize=(3,3))
ax.imshow(psim)
ax.set_xticks(0:length(pnames)-1)
ax.set_yticks(0:length(pnames)-1)
ax.set_xticklabels(pnames; rotation="vertical")
ax.set_yticklabels(pnames)
fig.tight_layout()
fig.savefig("program_similarity.pdf")


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

fig, axs = plt.subplots(1, 3; figsize=(7,3))
ax = axs[1]
ex = extrema(dbbsnmatric)
ax.hist(dbbsnmatric; bins=ex[begin]:ex[end])
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
fig.savefig("outcome_waitlist_distribution.pdf")
