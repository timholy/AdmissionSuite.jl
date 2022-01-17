using Admit
using Dates
using Test

function countby(list)
    counter = Dict{eltype(list),Int}()
    for item in list
        n = get(counter, item, 0)
        counter[item] = n+1
    end
    return counter
end

@testset "Admit.jl" begin
    @testset "normdate" begin
        pd = ProgramData(firstofferdate=Date("2021-02-11"), lastdecisiondate=Date("2021-04-15"))
        @test normdate(Date("2021-02-11"), pd) == 0.0f0
        @test normdate(Date("2021-04-15"), pd) == 1.0f0
        @test normdate(Date("2021-03-15"), pd) ≈  0.50793654f0
        @test normdate(Date("2021-01-01"), pd) ≈ -0.6507937f0
    end
    @testset "aggregate" begin
        Admit.addprogram("OldA")
        Admit.addprogram("OldB")
        Admit.addprogram("NewA")
        pd2019 = ProgramData(1, 2, 3, 4, today(), today())
        pd2020 = ProgramData(5, 10, 15, 20, today(), today())
        ph = Dict(ProgramKey("OldA", 2019) => pd2019,
                  ProgramKey("NewA", 2020) => pd2020,)
        pha = Admit.aggregate(ph, ("OldA" => "NewA",))
        @test pha[ProgramKey("NewA", 2020)] == pd2020
        @test pha[ProgramKey("NewA", 2019)] == pd2019
        pha = Admit.aggregate(ph, ("OldA" => ["NewA"],))
        @test pha[ProgramKey("NewA", 2020)] == pd2020
        @test pha[ProgramKey("NewA", 2019)] == pd2019
        pha = Admit.aggregate(ph, ("OldA" => ["NewA","NewA"],))
        @test pha[ProgramKey("NewA", 2020)] == pd2020
        # Due to integer rounding this next one is a bit funny
        @test pha[ProgramKey("NewA", 2019)] == ProgramData(2*round(Int, 1/2), 2, 2*round(Int, 3/2), 4, today(), today())
        ph = Dict(ProgramKey("OldA", 2019) => pd2019,
                  ProgramKey("OldB", 2019) => pd2020,)
        pha = Admit.aggregate(ph, ("OldA" => "NewA", "OldB" => "NewA"))
        pdc = pha[ProgramKey("NewA", 2019)]
        for fn in (:target_raw, :target_corrected, :nmatriculants, :napplicants)
            @test getfield(pdc, fn) == getfield(pd2019, fn) + getfield(pd2020, fn)
        end

        yd = Dict("OldA" => Outcome(5, 5), "NewA" => Outcome(3, 7))
        yda = Admit.aggregate(yd, ("OldA" => "NewA",))
        @test yda["NewA"] == Outcome(8, 12)
        @test !haskey(yda, "OldA")
        yda = Admit.aggregate(yd, ("OldA" => ["NewA"],))
        @test yda["NewA"] == Outcome(8, 12)
        @test !haskey(yda, "OldA")
        yd = Dict("OldA" => Outcome(4, 4), "NewA" => Outcome(1, 2), "NewB" => Outcome(3, 1))
        yda = Admit.aggregate(yd, ("OldA" => ["NewA", "NewB"],))
        @test yda["NewA"] == Outcome(3, 4)
        @test yda["NewB"] == Outcome(5, 3)

        Admit.delprogram("OldA")
        Admit.delprogram("OldB")
        Admit.delprogram("NewA")
    end

    @testset "Matching and matriculation probability" begin
        program_history = Dict(ProgramKey("NS", 2021) => ProgramData(slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                               ProgramKey("CB", 2021) => ProgramData(slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")),
        )
        @test Admit.compute_target(program_history, Date("2021-04-15")) == 20
        past_applicants = [(program="NS", rank=7, offerdate=Date("2021-01-13"), decidedate=Date("2021-03-26"), accept=true),
                           (program="NS", rank=3, offerdate=Date("2021-01-13"), decidedate=Date("2021-04-15"), accept=false),
                           (program="CB", rank=6, offerdate=Date("2021-03-25"), decidedate=Date("2021-04-15"), accept=true),
        ]
        past_applicants = [NormalizedApplicant(; app..., program_history) for app in past_applicants]

        applicant = NormalizedApplicant(; program="NS", rank=11, offerdate=Date("2021-01-13"), program_history)
        io = IOBuffer()
        show(io, applicant)
        str = String(take!(io))
        @test str == "NormalizedApplicant(NS, 2021, normrank=$(Float32(11/302)), normofferdate=0.0, )"

        # A match function that heavily weights normalized rank
        fmatch = match_function(σr=0.01, σt=Inf, progsim=(a,b)->true)
        like = @inferred(match_likelihood(fmatch, past_applicants, applicant, 0.0))
        @test like[3] > like[1] > like[2]
        @test matriculation_probability(like, past_applicants) > 0.95
        clike = cumsum(like)
        s = [select_applicant(clike, past_applicants) for i = 1:100]
        sc = first.(sort(collect(pairs(countby(s))); by=last))
        @test sc[end].program == "CB"    # best match is to rank 7/302 since it's closest to 6/160
        @test sc[end-1].program == "NS" && sc[end-1].normrank == Float32(7/302)

        # A match function that heavily weights offer date
        fmatch = match_function(σr=Inf, σt=0.3, progsim=(a,b)->true)
        like = match_likelihood(fmatch, past_applicants, applicant, 0.0)
        @test like[1] == like[2] == 1
        @test like[1] > like[3]
        @test 0.48 < matriculation_probability(like, past_applicants) < 0.52

        # Require program-specific matching
        fmatch = match_function(σr=0.01, σt=Inf)   # `progsim` default returns `a == b`
        like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-01-13"); program_history)
        @test like[1] > like[2]
        @test like[3] == 0

        # Excluding applicants who had already decided at this point in the season
        fmatch = match_function(σr=0.01, σt=Inf)
        like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-04-01"); program_history)
        @test like[2] > 0
        @test like[1] == like[3] == 0
    end

    @testset "Program similarity from program data" begin
        offerdat = Dict("CB" => (4, 100), "NS" => (5, 100))
        yielddat = Dict("CB" => (Outcome(0, 2), Outcome(2, 0)), "NS" => (Outcome(1, 1), Outcome(2, 1)))
        @test program_similarity("CB", "CB"; σsel=1e-6, σyield=1e-6, offerdata=offerdat, yielddata=yielddat) == 1
        @test program_similarity("CB", "NS"; σsel=1e-6, σyield=1e-6, offerdata=offerdat, yielddata=yielddat) == 0
        @test program_similarity("CB", "NS"; σsel=Inf,  σyield=Inf,  offerdata=offerdat, yielddata=yielddat) == 1
        @test program_similarity("CB", "NS"; σsel=0.01, σyield=Inf,  offerdata=offerdat, yielddata=yielddat) ≈ exp(-1/2)
        @test program_similarity("CB", "NS"; σsel=Inf,  σyield=sqrt(0.18), offerdata=offerdat, yielddata=yielddat) ≈ exp(-1/2)
    end

    @testset "I/O, program data, program similarity" begin
        io = IOBuffer()
        print(io, Outcome(3, 5))
        @test String(take!(io)) == "(d=3, a=5)"

        program_history = read_program_history(joinpath(@__DIR__, "data", "programdata.csv"))
        @test length(program_history) == 6
        past_applicants = read_applicant_data(joinpath(@__DIR__, "data", "applicantdata.csv"); program_history)
        @test length(past_applicants) == 36
        new_applicants = [(program="NS", rank=7, offerdate=Date("2021-01-13")),
                        (program="NS", rank=3, offerdate=Date("2021-01-13")),
                        (program="CB", rank=6, offerdate=Date("2021-03-25")),
        ]
        new_applicants = [NormalizedApplicant(; app..., program_history) for app in new_applicants]
        # The data were set up to be symmetric except for date
        od = offerdata(past_applicants, program_history)
        @test od["NS"] == od["CB"] == (18, 105)
        yd = yielddata(Outcome, past_applicants)
        @test yd["NS"] == yd["CB"] == Outcome(9, 9)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
        @test yd["NS"] == (Outcome(0,1), Outcome(1,1), Outcome(8,7))
        @test yd["CB"] == (Outcome(1,0), Outcome(0,1), Outcome(8,8))
        @test program_similarity("NS", "CB"; σsel=0.1, offerdata=od, yielddata=yd) == 1
        y1 = [0, 1, 1, 1, 8, 7]; y1 = y1/sum(y1)
        y2 = [1, 0, 0, 1, 8, 8]; y2 = y2/sum(y2)
        @test program_similarity("NS", "CB"; σyield=0.1, offerdata=od, yielddata=yd) ≈ exp(-sum((y1-y2).^2)/(0.02))
        fsim = cached_similarity(0.1, 0.1; offerdata=od, yielddata=yd)
        @test fsim("NS", "NS") == fsim("CB", "CB") == 1
        @test fsim("NS", "CB") ≈ exp(-sum((y1-y2).^2)/(0.02))

        fmatch = match_function(σr=0.05, σt=0.5, progsim=fsim)
        pmatric = map(new_applicants) do applicant
            like = match_likelihood(fmatch, past_applicants, applicant, 0.0)
            matriculation_probability(like, past_applicants)
        end
        @test all(x -> 0 <= x <= 1, pmatric)
    end

    @testset "Model training" begin
        substnan(A) = [isnan(a) ? oftype(a, -Inf) : a for a in A]

        # Set up no overall difference among programs
        program_history = Dict{ProgramKey,ProgramData}()
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=100, firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        offerdates  = vec([Date("$yr-0$m-15") for yr in 2019:2021, m in 1:2])
        decidedates = vec([Date("$yr-0$m-15") for yr in 2019:2021, m in 3:4])
        σsels = σyields = σrs = σts = [Inf, 0.01]
        # Test lower-level call (for a single year) with rank determining acceptance
        past_applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=r>3, program_history) for prog in ("CB", "NS"), r in 1:6, (od,dd) in zip(offerdates[begin:end-1], decidedates[begin:end-1])])
        applicants      = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=offerdates[end], decidedate=decidedates[end], accept=r>3, program_history) for prog in ("CB", "NS"), r in 1:6])
        # Just the program yield
        yes = yield_errors(σsels, σyields; applicants=vcat(applicants, past_applicants), program_history)
        @test yes == [0 0; 0 0]
        # Each applicant
        od = offerdata(past_applicants, program_history)
        yd = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
        @test match_correlation(0.2, Inf, Inf, Inf; applicants, past_applicants, offerdata=od, yielddata=yd) == 0
        @test match_correlation(Inf, 0.2, Inf, Inf; applicants, past_applicants, offerdata=od, yielddata=yd) == 0
        @test 0.8 < match_correlation(Inf, Inf, 0.2, Inf; applicants, past_applicants, offerdata=od, yielddata=yd) < 0.9
        @test match_correlation(Inf, Inf, Inf, 0.2; applicants, past_applicants, offerdata=od, yielddata=yd) == 0
        @test match_correlation(Inf, Inf, 0.001, Inf; applicants, past_applicants, offerdata=od, yielddata=yd) > 0.999
        @test match_correlation(Inf, Inf, 0.001, Inf; applicants, past_applicants, offerdata=od, yielddata=yd, ptail=0.5) == 0
        @test match_correlation(Inf, Inf, 0.001, Inf; applicants, past_applicants, offerdata=od, yielddata=yd, minfrac=0.15) > 0.999
        @test isnan(match_correlation(Inf, Inf, 0.001, Inf; applicants, past_applicants, offerdata=od, yielddata=yd, minfrac=0.25))
        # Case 1: rank is meaningful, nothing else is
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=r>3, program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates if year(od) == year(dd)])
        corarray = match_correlation(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0.25)
        @test all(iszero, corarray[:,:,1,:])
        @test isnan(corarray[2,2,2,2])
        idx = argmax(substnan(corarray))
        @test idx[3] == 2
        @test idx[4] == 1
        # Case 2: offer date is meaningful, nothing else is
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=month(od)==1, program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates if year(od) == year(dd)])
        corarray = match_correlation(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0.25)
        @test isnan(corarray[2,2,2,2])
        idx = argmax(substnan(corarray))
        @test idx[3] == 1
        @test idx[4] == 2
        # Case 3: program yield timing and rank are meaningful, nothing else is
        progmonth = Dict("CB" => 3, "NS" => 4)
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=r>=progmonth[prog] && month(dd)==progmonth[prog], program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates if year(od) == year(dd)])
        yes = yield_errors(σsels, σyields; applicants, program_history)
        @test yes[1,1] ≈ yes[2,1]
        @test yes[1,2] == yes[2,2] == 0
        @test yes[1,1] > 0
        corarray = match_correlation(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0)
        @test corarray[1,:,:,:] ≈ corarray[2,:,:,:]
        @test corarray[:,:,:,1] ≈ corarray[:,:,:,2]
        @test !(corarray[:,1,:,:] ≈ corarray[:,2,:,:])
        @test !(corarray[:,:,1,:] ≈ corarray[:,:,2,:])
        idx = argmax(substnan(corarray))
        @test idx[2] == idx[3] == 2
        # Case 4: program selectivity and rank are meaningful, nothing else is
        progapps = Dict("CB" => 100, "NS" => 200)
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=progapps[prog], firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        applicants = vec([NormalizedApplicant(; program=prog, rank=r*progapps[prog]÷100, offerdate=od, decidedate=dd, accept=prog=="CB" ? isodd(r) : iseven(r), program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates if year(od) == year(dd)])
        corarray = match_correlation(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0)
        @test corarray[:,1,:,:] ≈ corarray[:,2,:,:]
        @test corarray[:,:,:,1] ≈ corarray[:,:,:,2]
        @test !(corarray[1,:,:,:] ≈ corarray[2,:,:,:])
        @test !(corarray[:,:,1,:] ≈ corarray[:,:,2,:])
        idx = argmax(substnan(corarray))
        @test idx[1] == idx[3] == 2
        # Case 5: yield with selectivity and yield
        applicants = vec([NormalizedApplicant(; program=prog, rank=r*progapps[prog]÷100, offerdate=Date(yr, 2, 1), decidedate=Date(yr, 4, 15), accept=prog=="CB" ? true : r < 3, program_history) for prog in ("CB", "NS"), r in 1:6, yr in 2019:2021])
        yes = yield_errors(σsels, σyields; applicants, program_history)
        @test yes[1,1] > 0.2
        @test yes[2,1] < 0.01
    end

    @testset "Wait list" begin
        program_history = Dict{ProgramKey,ProgramData}()
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=3, napplicants=100, firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        # Top-ranked applicants decline late, lower-ranked applicants accept early
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=Date("$yr-01-13"), decidedate=r>3 ? Date("$yr-01-15") : Date("$yr-04-15"), accept=r>3+(prog=="NS")-(yr==2019), program_history) for prog in ("CB", "NS"), r in 1:7, yr in 2019:2021])
        past_applicants = filter(app -> app.season  < 2021, applicants)
        test_applicants = filter(app -> app.season == 2021, applicants)
        fmatch = match_function(; σr=0.0001f0)
        ## Sending out offers
        program_candidates = Dict(map(("CB", "NS")) do prog
            list = sort!(filter(app->app.program == prog, test_applicants); by=app->app.normrank)
            prog => list
            # # Add one more applicant
            # prog => push!(list, NormalizedApplicant(; program=prog, rank=7, offerdate=Date("2021-01-13"), decidedate=Date("2021-01-20"), accept=true, program_history))
        end)
        program_offers, _ = initial_offers!(fmatch, program_candidates, past_applicants, Date("2021-01-01"), 0.25; program_history)
        @test all(list -> length(list) == 6, values(program_offers))
        @test all(list -> length(list) == 1, values(program_candidates))
        # By 1/16, many decisions would have been rendered. CB got all 3, NS got 2.
        (nmatric, _), (_, pq) = add_offers!(fmatch, program_offers, program_candidates, past_applicants, Date("2021-01-16"), 0.25; program_history)
        @test length(program_offers["NS"]) == 7
        @test length(program_offers["CB"]) == 6
        @test length(program_candidates["NS"]) == 0
        @test length(program_candidates["CB"]) == 1
        @test pq["NS"] > pq["CB"]
        # Using random applicants. This is useful for setting the initial number of accepts.
        # The following test assumes σt = Inf (as it is above)
        fake_candidates1 = generate_fake_candidates(program_history, 2021)
        fake_offers1, _ = initial_offers!(fmatch, fake_candidates1, past_applicants, Date("2021-01-01"); program_history)
        fake_candidates2 = generate_fake_candidates(program_history, 2021, Dict("CB" => Date.(["2021-01-13", "2021-02-02"])))
        fake_offers2, _ = initial_offers!(fmatch, fake_candidates2, past_applicants, Date("2021-01-01"); program_history)
        dictcount(d) = Dict(key=>length(val) for (key,val) in d)
        @test dictcount(fake_offers1) == dictcount(fake_offers2)

        # Check that we can use -σthresh to generate the number of candidates for the wait list
        fake_candidates3 = generate_fake_candidates(program_history, 2021, Dict("CB" => Date.(["2021-01-13", "2021-02-02"])))
        fake_offers3a, nmatrica = initial_offers!(fmatch, deepcopy(fake_candidates3), past_applicants, Date("2021-01-01"),  2; program_history)
        fake_offers3b, nmatricb = initial_offers!(fmatch, deepcopy(fake_candidates3), past_applicants, Date("2021-01-01"), -2; program_history)
        target = Admit.compute_target(program_history, 2021);
        @test nmatrica.val +   nmatrica.err < target
        @test nmatrica.val + 2*nmatrica.err >= target
        @test nmatricb.val - 2*nmatricb.err >= target
        @test nmatricb.val - 3*nmatricb.err < target

        ## Analyzing wait list
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=Date("$yr-01-13"), decidedate=r>3 ? Date("$yr-01-15") : Date("$yr-04-15"), accept=r>3+(prog=="NS")-(yr==2019), program_history) for prog in ("CB", "NS"), r in 1:6, yr in 2019:2021])
        past_applicants = filter(app -> app.season  < 2021, applicants)
        test_applicants = filter(app -> app.season == 2021, applicants)
        actual_yield = Dict("CB" => 3, "NS" => 0)
        nmatric, progstatus = wait_list_analysis(fmatch, past_applicants, test_applicants, Date("2021-01-13"); program_history, actual_yield)
        @test nmatric ≈ 6
        @test progstatus["CB"].nmatriculants.val ≈ 3.5 && progstatus["CB"].nmatriculants.err ≈ 0.5
        @test progstatus["NS"].nmatriculants.val ≈ 2.5 && progstatus["NS"].nmatriculants.err ≈ 0.5
        @test progstatus["NS"].priority > progstatus["CB"].priority
        @test progstatus["CB"].poutcome == 1
        @test progstatus["NS"].poutcome == 0
        # Just make sure this runs
        nmatric, progstatus = wait_list_analysis(fmatch, past_applicants, test_applicants, Date("2021-01-13"); program_history)
        @test nmatric ≈ 6
        # Also with unknown decision dates
        test_applicants = [NormalizedApplicant(app; normdecidedate=missing) for app in test_applicants]
        nmatric, progstatus = wait_list_analysis(fmatch, past_applicants, test_applicants, Date("2021-01-13"); program_history)
        @test nmatric ≈ 6
    end

    @testset "High-value" begin
        substnan(A) = [isnan(a) ? oftype(a, -Inf) : a for a in A]

        newprogs = ("ProgA", "ProgB")
        for prog in newprogs
            Admit.addprogram(prog)
        end
        # Impact of incorporating high-value applicant status into similarity function.
        # Such applicants are less likely to come because competition for them across institutions is high.
        program_history = Dict{ProgramKey,ProgramData}()
        for prog in ("ProgA", "ProgB"), yr in 2011:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=100, firstofferdate=Date("$yr-01-01"), lastdecisiondate=Date("$yr-04-15"))
        end
        # Among past applicants, top-ranking and URM candidates are less likely to accept.
        function linpair(r, r1v1::Pair, r2v2::Pair)
            r1, v1 = r1v1
            r2, v2 = r2v2
            r1 <= r <= r2 || throw(ArgumentError("$r is outside the bounds [$r1, $r2]"))
            f = (r - r1)/(r2 - r1)
            return f*v2 + (1-f)*v1
        end
        acceptp(r, urm::Bool) = linpair(r, 1=>0.2, 30=>0.7) * (urm ? 0.5 : 1.0)
        function fmatch_creator(σr, σurm; kwargs...)
            return function(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})
                dr = template.normrank - applicant.normrank
                du = template.applicantdata.urmdd - applicant.applicantdata.urmdd
                return exp(-dr^2/(2*σr^2) - du^2/(2*σurm^2))
            end
        end
        σrs   = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0]
        σurms = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0]
        nA = nB = 0
        for i = 1:20
            past_applicants = vec([(urm = (r + yr) % 3 == 0; NormalizedApplicant(; program=prog, urmdd=urm, rank=r, offerdate=Date("$yr-01-01"), accept=rand()<acceptp(r, urm), program_history)) for prog in ("ProgA", "ProgB"), r in 1:30, yr in 2016:2020])
            corarray = match_correlation(fmatch_creator, σrs, σurms; applicants=past_applicants, program_history, minfrac=0.05)
            idx = argmax(substnan(corarray))
            σr, σurm = σrs[idx[1]], σurms[idx[2]]
            yr = 2021
            # ProgA puts more low-probability applicants high on their list
            prog_candidates = Dict("ProgA" => vec([(urm = (r + yr) % 3 == 0; NormalizedApplicant(; program="ProgA", urmdd=urm,   rank=r, offerdate=Date("$yr-01-01"), program_history)) for r in 1:30]),
                                   "ProgB" => vec([                          NormalizedApplicant(; program="ProgB", urmdd=false, rank=r, offerdate=Date("$yr-01-01"), program_history)  for r in 1:30]))
            offers, _ = initial_offers!(fmatch_creator(σr, σurm), prog_candidates, past_applicants, Date("2021-01-01"); program_history)
            nA += length(offers["ProgA"])
            nB += length(offers["ProgB"])
        end
        @test nA > nB

        io = IOBuffer()
        show(io, NormalizedApplicant(; program="ProgA", urmdd=true, rank=2, offerdate=Date("2021-01-01"), accept=true, program_history))
        str = String(take!(io))
        @test str == "NormalizedApplicant(urmdd=true, ProgA, 2021, normrank=0.02, normofferdate=0.0, accept=true)"

        for prog in newprogs
            Admit.delprogram(prog)
        end
    end

    @testset "Web" begin
        # We don't test that it renders, but we do check all the callbacks
        progs = ["BBSB","BIDS","CB","CSB","DRSCB","EEPB","HSG","IMM","MCB","MGG","MMMP","NS","PMB"]
        yrs = 2017:2022
        program_history = Dict{ProgramKey,ProgramData}()
        for yr in yrs, prog in progs
            slots=rand(4:13)
            program_history[ProgramKey(prog, yr)] = ProgramData(; slots, napplicants=2*slots, firstofferdate=Date("$yr-02-01"), lastdecisiondate=Date("$yr-04-15"))
        end
        target = Admit.compute_target(program_history, last(yrs))
        past_applicants = NormalizedApplicant[]
        for yr in first(yrs):last(yrs)-1
            fk = Admit.generate_fake_candidates(program_history, yr; decided=true)
            for prog in progs
                append!(past_applicants, fk[prog])
            end
        end
        yr = last(yrs)
        fixeddate = Date("$(yr)-02-28")
        program_offer_dates = Dict(prog => Date("$yr-02-01"):Day(1):Date("$yr-04-15") for prog in progs)
        fk = Admit.generate_fake_candidates(program_history, yr, decided=0.3, program_offer_dates, tnow=fixeddate)
        applicants = NormalizedApplicant[]
        for prog in progs
            append!(applicants, fk[prog])
        end

        app = manage_offers(()->past_applicants, ()->applicants, ()->program_history, ()->fixeddate)
        @test isa(app, Admit.Dash.DashApp)
        app = manage_offers(()->past_applicants, ()->applicants, ()->program_history, fixeddate)
        @test isa(app, Admit.Dash.DashApp)
        app = manage_offers(()->past_applicants, ()->applicants, ()->program_history, fixeddate; σthresh=1.5)
        @test isa(app, Admit.Dash.DashApp)
        fmatch = match_function()
        tab = Admit.render_tab_summary(fmatch,
            past_applicants, applicants, fixeddate, program_history, target, 2)
        @test isa(tab, Admit.DashBase.Component)
        prog = "MMMP"
        tab = Admit.render_program_zoom(fmatch, past_applicants,
            filter(app->app.program==prog, applicants), fixeddate, program_history[ProgramKey(prog,last(yrs))], prog)
        @test isa(tab, Admit.DashBase.Component)
        tab = Admit.render_tab_initial(fmatch,
            past_applicants, applicants, fixeddate, program_history, target, 2)
        @test isa(tab, Admit.DashBase.Component)
        tab = Admit.render_internals(fmatch, past_applicants, applicants, fixeddate, program_history, Admit.default_similarity, progs)
        @test isa(tab, Admit.DashBase.Component)
    end
end
