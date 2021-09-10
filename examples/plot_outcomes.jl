using PyPlot: PyPlot, plt
using Colors
using Distributions
using MultivariateStats
using GLM

pnames = sort(collect(keys(filter(pr -> 2021 ∈ pr.second, AdmissionsSimulation.program_range))))  # current programs
programcolors = hex.(distinguishable_colors(length(pnames), [colorant"white"]; dropseed=true))

# Program similarity
if isdefined(@__MODULE__, :progsim_pg)
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
    fig, axs = plt.subplots(1, 2; figsize=(6,3))
    ax = axs[1]
    sel = [(od = get(offerdat, n, (0, 0)); od[1]/(od[1] + od[2])) for n in pnames]
    ax.bar(0:length(pnames)-1, 100*sel)
    ax.set_xticks(0:length(pnames)-1)
    ax.set_xticklabels(pnames; rotation="vertical")
    ax.set_ylabel("% admitted")
    ax = axs[2]
    len(::Type{NTuple{N,T}}) where {N,T} = N
    accepts = zeros(len(valtype(yielddat)), length(pnames))
    declines = zero(accepts)
    for (j, n) in enumerate(pnames)
        local yd = get(yielddat, n, AdmissionsSimulation.null(valtype(yielddat)))
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
        for (ln,col) in zip(lns, programcolors)
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
end

if isdefined(@__MODULE__, :progcorrelations)
    fig, ax = plt.subplots(1, 1; figsize=(5,3))
    cs = [progcorrelations[prog] for prog in pnames]
    y = length(pnames):-1:1
    ax.barh(y, cs)
    ax.set_yticks(y)
    ax.set_yticklabels(pnames)
    ax.set_xlabel("Rank/accept correlation")
    fig.tight_layout()
    fig.savefig("rank-accept_correlation.pdf")
end

# Program history
if isdefined(@__MODULE__, :program_history)
    fig, ax = plt.subplots(1, 1; figsize=(4,4))
    pds = valtype(program_history)[]
    shownprogs, proglines = String[], []
    progxend, progyend = Float64[], Float64[]
    progxbeg, progybeg = Float64[], Float64[]
    for (prog, col) in zip(pnames, programcolors)
        empty!(pds)
        for yr in 2017:2021
            pk = ProgramKey(prog, yr)
            if haskey(program_history, pk)
                push!(pds, program_history[pk])
            end
        end
        if !isempty(pds)
            x = [pd.napplicants for pd in pds]
            y = [pd.target_corrected for pd in pds]
            push!(proglines, ax.plot(x, y, color="#"*col)[1])
            push!(shownprogs, prog)
            ax.plot(x[end], y[end], marker="x", color="#"*col)
            push!(progxend, x[end])
            push!(progyend, y[end])
            push!(progxbeg, x[begin])
            push!(progybeg, y[begin])
        end
    end
    _, xhi = ax.get_xlim()
    ax.set_xlim((0, xhi))
    _, yhi = ax.get_ylim()
    ax.set_ylim((0, yhi))
    ols = lm(@formula(y~x), DataFrame("x"=>progxend, "y"=>progyend))
    ax.plot([0, xhi], predict(ols, DataFrame("x"=>[0, xhi])), color="lightgray", linestyle="--")
    ols = lm(@formula(y~x), DataFrame("x"=>progxbeg, "y"=>progybeg))
    ax.plot([0, xhi], predict(ols, DataFrame("x"=>[0, xhi])), color="lightgray", linestyle=":")
    ax.legend(proglines, shownprogs)
    ax.set_xlabel("# applicants")
    ax.set_ylabel("target")
    fig.tight_layout()
    fig.savefig("program_history.pdf")
end

# Distribution of outcomes from vantage point of beginning of the season
if isdefined(@__MODULE__, :nmatrics_wl)
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
end

if isdefined(@__MODULE__, :rollingprojections)
    σthresh = 2
    class_size_projection = rollingprojections[σthresh]
    d = first.(class_size_projection)
    sz = last.(class_size_projection)
    msz, σsz = (x->x.val).(sz), (x->x.err).(sz)
    fig, ax = plt.subplots(1, 1)
    # ax.errorbar(d, msz, yerr=σsz)
    ln = ax.plot(d, msz)
    hexcolor = only(ln).get_color()
    ax.fill_between(d, msz - σsz, msz + σsz, color=hexcolor*"60")
    ax.set_xlabel("Date")
    for lbl in ax.get_xticklabels()
        lbl.set_rotation(90)
    end
    ax.set_ylabel("Projected class size")
    for (i, (d, list)) in enumerate(rollingoffers[σthresh])
        if !isempty(list)
            ax.annotate(string(length(list)), (d, msz[i]+σsz[i]+2), color="red")
        end
    end
    N = sum(tgts)
    yl = ax.get_ylim()
    if N > yl[2]
        ax.set_ylim((yl[1], N+2))
    end
    ax.plot(d[[begin,end]], [N,N], "k--")
    fig.tight_layout()
    fig.savefig("rolling_waitlist.pdf")
end

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
