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
        # Set up no overall difference among programs
        program_history = Dict{ProgramKey,ProgramData}()
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=100, firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        offerdates  = vec([Date("$yr-0$m-15") for yr in 2019:2021, m in 1:2])
        decidedates = vec([Date("$yr-0$m-15") for yr in 2019:2021, m in 3:4])
        σsels = σyields = σrs = σts = [0.01, Inf]
        # Case 1: rank is meaningful, nothing else is
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=r>3, program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates])
        np = net_loglike(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0.25)
        @test all(iszero, np[:,:,2,:])
        @test isinf(np[1,1,1,1])
        idx = argmax(np)
        @test idx[3] == 1
        @test idx[4] == 2
        # Case 2: offer date is meaningful, nothing else is
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=month(od)==1, program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates])
        np = net_loglike(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0.25)
        @test isinf(np[1,1,1,1])
        idx = argmax(np)
        @test idx[3] == 2
        @test idx[4] == 1
        # Case 3: program yield timing and rank are meaningful, nothing else is
        progmonth = Dict("CB" => 3, "NS" => 4)
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=od, decidedate=dd, accept=r>=progmonth[prog] && month(dd)==progmonth[prog], program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates])
        np = net_loglike(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0)
        @test np[1,:,:,:] ≈ np[2,:,:,:]
        @test np[:,:,:,1] ≈ np[:,:,:,2]
        @test !(np[:,1,:,:] ≈ np[:,2,:,:])
        @test !(np[:,:,1,:] ≈ np[:,:,2,:])
        idx = argmax(np)
        @test idx[2] == idx[3] == 1
        # Case 4: program selectivity and rank are meaningful, nothing else is
        progapps = Dict("CB" => 100, "NS" => 200)
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=progapps[prog], firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        applicants = vec([NormalizedApplicant(; program=prog, rank=r*progapps[prog]÷100, offerdate=od, decidedate=dd, accept=prog=="CB" ? isodd(r) : iseven(r), program_history) for prog in ("CB", "NS"), r in 1:6, od in offerdates, dd in decidedates])
        np = net_loglike(σsels, σyields, σrs, σts; applicants, program_history, minfrac=0)
        @test np[:,1,:,:] ≈ np[:,2,:,:]
        @test np[:,:,:,1] ≈ np[:,:,:,2]
        @test !(np[1,:,:,:] ≈ np[2,:,:,:])
        @test !(np[:,:,1,:] ≈ np[:,:,2,:])
        idx = argmax(np)
        @test idx[1] == idx[3] == 1
    end

    @testset "Wait list" begin
        program_history = Dict{ProgramKey,ProgramData}()
        for prog in ("CB", "NS"), yr in 2019:2021
            program_history[ProgramKey(prog, yr)] = ProgramData(slots=10, napplicants=100, firstofferdate=Date("$yr-01-13"), lastdecisiondate=Date("$yr-04-15"))
        end
        # Top-ranked applicants decline late, lower-ranked applicants accept early
        applicants = vec([NormalizedApplicant(; program=prog, rank=r, offerdate=Date("$yr-01-13"), decidedate=r>3 ? Date("$yr-01-15") : Date("$yr-04-15"), accept=r>3+(prog=="NS")-(yr==2019), program_history) for prog in ("CB", "NS"), r in 1:6, yr in 2019:2021])
        past_applicants = filter(app -> app.season  < 2021, applicants)
        test_applicants = filter(app -> app.season == 2021, applicants)
        fmatch = match_function(; σr=0.0001f0)
        actual_yield = Dict("CB" => 3, "NS" => 0)
        nmatric, progstatus = wait_list_offers(fmatch, past_applicants, test_applicants, Date("2021-01-13"); program_history, actual_yield)
        @test nmatric ≈ 6
        @test progstatus["CB"].nmatriculants.val ≈ 3.5 && progstatus["CB"].nmatriculants.err ≈ 0.5
        @test progstatus["NS"].nmatriculants.val ≈ 2.5 && progstatus["NS"].nmatriculants.err ≈ 0.5
        @test progstatus["NS"].priority > progstatus["CB"].priority
        @test progstatus["CB"].poutcome == 1
        @test progstatus["NS"].poutcome == 0
        # Just make sure this runs
        nmatric, progstatus = wait_list_offers(fmatch, past_applicants, test_applicants, Date("2021-01-13"); program_history)
        @test nmatric ≈ 6
    end
end
