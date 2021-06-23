using AdmissionsSimulation
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

@testset "AdmissionsSimulation.jl" begin
    @testset "aggregate" begin
        AdmissionsSimulation.addprogram("OldA")
        AdmissionsSimulation.addprogram("OldB")
        AdmissionsSimulation.addprogram("NewA")
        pd2019 = ProgramData(1, 2, 3, 4, today(), today())
        pd2020 = ProgramData(5, 10, 15, 20, today(), today())
        ph = Dict(ProgramKey("OldA", 2019) => pd2019,
                  ProgramKey("NewA", 2020) => pd2020,)
        pha = AdmissionsSimulation.aggregate(ph, ("OldA" => "NewA",))
        @test pha[ProgramKey("NewA", 2020)] == pd2020
        @test pha[ProgramKey("NewA", 2019)] == pd2019
        ph = Dict(ProgramKey("OldA", 2019) => pd2019,
                  ProgramKey("OldB", 2019) => pd2020,)
        pha = AdmissionsSimulation.aggregate(ph, ("OldA" => "NewA", "OldB" => "NewA"))
        pdc = pha[ProgramKey("NewA", 2019)]
        for fn in (:target_raw, :target_corrected, :nmatriculants, :napplicants)
            @test getfield(pdc, fn) == getfield(pd2019, fn) + getfield(pd2020, fn)
        end
        AdmissionsSimulation.delprogram("OldA")
        AdmissionsSimulation.delprogram("OldB")
        AdmissionsSimulation.delprogram("NewA")
    end
    @testset "Targets" begin
        # Test the "don't game the system" ethic
        program_applicants = Dict("ATMP" => 10, "BTMP" => 10, "CTMP" => 10)
        fiis = Dict("ATMP" => 2, "BTMP" => 2, "CTMP" => 2)
        tgts1 = targets(program_applicants, fiis, 6)
        @test all(pr -> pr.second ≈ 2, tgts1)
        program_applicants2 = Dict("AB" => 20, "CTMP" => 10)  # combine programs A and B
        fiis = Dict("AB" => 4, "CTMP" => 2)
        tgts2 = targets(program_applicants2, fiis, 6)
        @test tgts2["AB"] ≈ 4
        @test tgts2["CTMP"] ≈ 2
        tgts3, _ = targets(program_applicants2, fiis, 6, 3)
        @test tgts3["AB"] ≈ 3
        @test tgts3["CTMP"] ≈ 3
        # A more realistic test that involves parsing etc
        program_applicants = Dict("BBSB" => 10, "BIDS" => 10, "HSG" => 10)
        facrecords = read_faculty_data(joinpath(@__DIR__, "data", "facultyinvolvement.csv"))
        @test facrecords["fac1"].service == ["B" => Service(0, 1)]
        @test facrecords["fac2"].service == ["BIDS" => Service(2, 0)]
        @test facrecords["fac3"].service == ["HSG" => Service(5, 0)]
        @test facrecords["fac4"].service == ["BIDS" => Service(3, 0), "HSG" => Service(3, 0)]
        @test facrecords["fac5"].service == ["B" => Service(0, 1), "HSG" => Service(0, 1)]
        @test facrecords["fac6"].service == ["B" => Service(0, 1), "HSG" => Service(3, 0)]
        facrecords = AdmissionsSimulation.aggregate(facrecords, AdmissionsSimulation.default_program_substitutions)
        progsvc = program_service(facrecords)
        @test progsvc["BIDS"] == Service(5, 0)
        @test progsvc["BBSB"] == Service(0, 3)
        @test progsvc["HSG"] == Service(11, 1)
        sc = calibrate_service(progsvc)
        @test sc == calibrate_service(facrecords)
        @test sc.c_per_i ≈ 1/11
        @test AdmissionsSimulation.total(Service(1, 0), sc)  ≈ 11.1/11
        @test AdmissionsSimulation.total(Service(0, 1), sc)  ≈ 11.1
        @test AdmissionsSimulation.total(Service(11, 1), sc) ≈ 11.1       # we use max over interview and committees
        @test AdmissionsSimulation.total(Service(12, 1), sc) ≈ 12/11 * 11.1
        facs, progs, E = faculty_effort(facrecords, 2021:2021; sc)
        fiis = Dict(zip(progs, faculty_involvement(E; scheme=:thresheffort)))
        @test fiis["BBSB"] == 3
        @test fiis["BIDS"] == 2
        @test fiis["HSG"] == 4
        fiis = Dict(zip(progs, faculty_involvement(E; annualthresh=5, scheme=:thresheffort)))
        @test fiis["BBSB"] == 3
        @test fiis["BIDS"] == 1   # now fac2 is under threshold
        @test fiis["HSG"] == 4
        # Now that we've tested it, everything is easier without `sc`
        finaldate = Date("2021-12-31")  # set timer to end of 2021
        daterange = Date("2021-01-01"):Day(1):finaldate
        facs, progs, E = faculty_effort(facrecords, daterange; finaldate)
        @test progs == ["BBSB", "BIDS", "HSG"]
        @test E ≈ [10 0 0; 0 2 0; 0 0 5; 0 3 3; 10 0 10; 10 0 3]
        fiis = Dict(zip(progs, faculty_involvement(E; annualthresh=2.001, scheme=:thresheffort)))
        @test fiis["BBSB"] == 3
        @test fiis["BIDS"] == 1
        @test fiis["HSG"] == 4
        fiis = Dict(zip(progs, faculty_involvement(E; annualthresh=2.001, scheme=:normeffort)))
        @test fiis["BBSB"] ≈ 1 + 1/2 + 10/13
        @test fiis["BIDS"] ≈ 1/2
        @test fiis["HSG"] ≈ 1 + 1/2 + 1/2 + 3/13
        fiis = Dict(zip(progs, faculty_involvement(E; annualthresh=5.001, scheme=:normeffort)))
        @test fiis["BBSB"] ≈ 1 + 1/2 + 10/13
        @test fiis["BIDS"] ≈ 1/2              # fac4: 3 hrs isn't enough to qualify on own, but sum is
        @test fiis["HSG"] ≈ 1/2 + 1/2 + 3/13
        fiis = Dict(zip(progs, faculty_involvement(E; scheme=:effortshare)))
        @test fiis["BBSB"] ≈ 1 + 1/2 + 1
        @test fiis["BIDS"] ≈ 2
        @test fiis["HSG"] ≈ 1 + 1/2
        # Make sure date defaults are sensible
        daterange2020 = Date("2020-01-01"):Day(1):Date("2020-12-30") # one less due to leap year
        _, _, E2020 = faculty_effort(facrecords, daterange2020)   # `today()` should not influence outcomes by default
        @test E2020[:, [1,3]] ≈ E[:, [1,3]]     # BIDS wasn't around in 2020
        # Degenerate case
        fiis = Dict(zip(["A", "B"], faculty_involvement([0 0; 1 0]; scheme=:effortshare)))
        @test fiis["A"] ≈ 1
        @test fiis["B"] == 0
        # Invariance against merge/split
        # A cyclic effort matrix (4 faculty, 4 programs, 3 efforts)
        newprogs = ("ProgA", "ProgB", "ProgC", "ProgD")
        for prog in newprogs
            AdmissionsSimulation.addprogram(prog)
        end
        facrecs = [(; :Faculty=>"fac1", Symbol("DBBS Approval Date")=> "01/02/2020", Symbol("Primary Program") => "ProgA", Symbol("Secondary Program") => "ProgB", Symbol("Tertiary Program") => "ProgC",
                      Symbol("INTERVIEW ProgA") => 1, Symbol("INTERVIEW ProgB") => 1, Symbol("INTERVIEW ProgC") => 1),
                   (; :Faculty=>"fac2", Symbol("DBBS Approval Date")=> "01/02/2020", Symbol("Primary Program") => "ProgB", Symbol("Secondary Program") => "ProgC", Symbol("Tertiary Program") => "ProgD",
                      Symbol("INTERVIEW ProgB") => 1, Symbol("INTERVIEW ProgC") => 1, Symbol("INTERVIEW ProgD") => 1),
                   (; :Faculty=>"fac3", Symbol("DBBS Approval Date")=> "01/02/2020", Symbol("Primary Program") => "ProgC", Symbol("Secondary Program") => "ProgD", Symbol("Tertiary Program") => "ProgA",
                      Symbol("INTERVIEW ProgC") => 1, Symbol("INTERVIEW ProgD") => 1, Symbol("INTERVIEW ProgA") => 1),
                   (; :Faculty=>"fac4", Symbol("DBBS Approval Date")=> "01/02/2020", Symbol("Primary Program") => "ProgD", Symbol("Secondary Program") => "ProgA", Symbol("Tertiary Program") => "ProgB",
                      Symbol("INTERVIEW ProgD") => 1, Symbol("INTERVIEW ProgA") => 1, Symbol("INTERVIEW ProgB") => 1)]
        facrecs = read_faculty_data(facrecs, ["ProgA", "ProgB", "ProgC", "ProgD"]; iswarn=false)
        @test faculty_affiliations(facrecs) == Dict(prog=>1.0f0 for prog in newprogs)
        @test faculty_affiliations(facrecs, :primary) == faculty_affiliations(facrecs, :normalized) == faculty_affiliations(facrecs, :weighted)
        @test faculty_affiliations(facrecs, :all) == Dict(prog=>3.0f0 for prog in newprogs)
        @test_throws ArgumentError("scheme notascheme not recognized") faculty_affiliations(facrecs, :notascheme)
        faculty, programs, E = faculty_effort(facrecs, 2020:2020)
        @test faculty == ["fac1", "fac2", "fac3", "fac4"]
        @test programs == [newprogs...]
        @test E == [1 1 1 0; 0 1 1 1; 1 0 1 1; 1 1 0 1]
        fiis = faculty_involvement(E)
        @test fiis == [1, 1, 1, 1]
        mergepairs = ["ProgA"=>"ProgABC", "ProgB"=>"ProgABC", "ProgC"=>"ProgABC"]
        AdmissionsSimulation.addprogram("ProgABC")
        aggrecs = AdmissionsSimulation.aggregate(facrecs, mergepairs)
        @test faculty_affiliations(aggrecs, :primary) == Dict("ProgD"=>1, "ProgABC"=>3)               # good
        @test faculty_affiliations(aggrecs, :all) == Dict("ProgD"=>3, "ProgABC"=>4)                   # bad
        @test faculty_affiliations(aggrecs, :normalized) == Dict("ProgD"=>1.5, "ProgABC"=>2.5)        # bad
        @test faculty_affiliations(aggrecs, :weighted) ==  Dict("ProgD"=>4/3.0f0, "ProgABC"=>8/3.0f0) # bad
        _, programsagg, Eagg = faculty_effort(aggrecs, 2020:2020)
        @test Eagg ≈ [3 0; 2 1; 2 1; 2 1]
        fiis = Dict(zip(programsagg, faculty_involvement(Eagg)))
        @test fiis["ProgD"] ≈ 1      # good
        @test fiis["ProgABC"] ≈ 3    # good
        # The next is bad
        fiis = Dict(zip(programsagg, faculty_involvement(Eagg; scheme=:thresheffort, annualthresh=0.5)))
        @test fiis["ProgD"] ≈ 3
        @test fiis["ProgABC"] ≈ 4
        # The naive effortshare is *really* bad, because everyone does service to ABC so the threshold is too high for 3/4
        fiis = Dict(zip(programsagg, faculty_involvement(Eagg; scheme=:effortshare)))
        @test fiis["ProgD"] ≈ 3
        @test fiis["ProgABC"] ≈ 1
        # But if we support there are more faculty not serving either, then we get a more reasonable (but still poor) result
        fiis = Dict(zip(programsagg, faculty_involvement(Eagg; scheme=:effortshare, M=8)))
        @test fiis["ProgD"] ≈ 3/2
        @test fiis["ProgABC"] ≈ 5/2
        @test_throws ArgumentError faculty_involvement(Eagg; scheme=:notascheme)
        for prog in newprogs
            AdmissionsSimulation.delprogram(prog)
        end
        AdmissionsSimulation.delprogram("ProgABC")

        # Hyperbolic floors
        napplicants = Dict("ProgA"=>100, "ProgB"=>400)
        nfaculty = Dict("ProgA" => 25, "ProgB" => 36)
        tgts = targets(napplicants, nfaculty, 17)
        @test tgts["ProgA"] ≈ 5
        @test tgts["ProgB"] ≈ 12
        tgtsh, p = targets(napplicants, nfaculty, 17, 4.5)
        @test tgtsh == tgts
        @test p.n0 == 0
        @test p.N′ == 17
        tgtsh, p = targets(napplicants, nfaculty, 17, 6)
        @test tgtsh["ProgA"] ≈ 6
        @test tgtsh["ProgB"] ≈ 11
        # Linear floors (not exported because this scheme is an even bigger tax than hyperbolic floors on big programs)
        tgtsl = AdmissionsSimulation.targets_linear(napplicants, nfaculty, 17, 2)
        @test tgtsl["ProgA"] ≈ 2 + 5/17*13
        @test tgtsl["ProgB"] ≈ 2 + 12/17*13
    end

    @testset "Matching and matriculation probability" begin
        program_history = Dict(ProgramKey("NS", 2021) => ProgramData(slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                               ProgramKey("CB", 2021) => ProgramData(slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")),
        )
        past_applicants = [(program="NS", rank=7, offerdate=Date("2021-01-13"), decidedate=Date("2021-03-26"), accept=true),
                           (program="NS", rank=3, offerdate=Date("2021-01-13"), decidedate=Date("2021-04-15"), accept=false),
                           (program="CB", rank=6, offerdate=Date("2021-03-25"), decidedate=Date("2021-04-15"), accept=true),
        ]
        past_applicants = [NormalizedApplicant(; app..., program_history) for app in past_applicants]

        applicant = NormalizedApplicant(; program="NS", rank=11, offerdate=Date("2021-01-13"), program_history)

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
        program_offers = initial_offers!(fmatch, program_candidates, past_applicants, Date("2021-01-01"), 0.25; program_history)
        @test all(list -> length(list) == 6, values(program_offers))
        @test all(list -> length(list) == 1, values(program_candidates))
        # By 1/16, many decisions would have been rendered. CB got all 3, NS got 2.
        add_offers!(fmatch, program_offers, program_candidates, past_applicants, Date("2021-01-16"), 0.25; program_history)
        @test length(program_offers["NS"]) == 7
        @test length(program_offers["CB"]) == 6
        @test length(program_candidates["NS"]) == 0
        @test length(program_candidates["CB"]) == 1
        # Using random applicants. This is useful for setting the initial number of accepts.
        # The following test assumes σt = Inf (as it is above)
        fake_candidates1 = generate_fake_candidates(program_history, 2021)
        fake_offers1 = initial_offers!(fmatch, fake_candidates1, past_applicants, Date("2021-01-01"); program_history)
        fake_candidates2 = generate_fake_candidates(program_history, 2021, Dict("CB" => Date.(["2021-01-13", "2021-02-02"])))
        fake_offers2 = initial_offers!(fmatch, fake_candidates2, past_applicants, Date("2021-01-01"); program_history)
        dictcount(d) = Dict(key=>length(val) for (key,val) in d)
        @test dictcount(fake_offers1) == dictcount(fake_offers2)

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
    end
end
