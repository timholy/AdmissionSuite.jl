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
    @test sc[end].program == "CB"    # best match is to rank 11/302 ≈ 6/160
    @test sc[end-1].program == "NS" && sc[end-1].normrank == Float32(7/302)

    # A match function that heavily weights offer date
    fmatch = match_function(σr=Inf, σt=0.3, progsim=(a,b)->true)
    like = match_likelihood(fmatch, past_applicants, applicant, 0.0)
    @test like[1] == like[2] == 1
    @test like[1] > like[3]
    @test 0.48 < matriculation_probability(like, past_applicants) < 0.52

    # Require program-specific matching
    fmatch = match_function(σr=0.01, σt=Inf)
    like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-01-13"); program_history)
    @test like[1] > like[2]
    @test like[3] == 0

    # Excluding applicants who had already decided at this point in the season
    fmatch = match_function(σr=0.01, σt=Inf)
    like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-04-01"); program_history)
    @test like[2] > 0
    @test like[1] == like[3] == 0

    # I/O, program data, program similarity
    program_history = read_program_history(joinpath(@__DIR__, "data", "programdata.csv"))
    new_applicants = [(program="NS", rank=7, offerdate=Date("2021-01-13")),
                      (program="NS", rank=3, offerdate=Date("2021-01-13")),
                      (program="CB", rank=6, offerdate=Date("2021-03-25")),
    ]
    new_applicants = [NormalizedApplicant(; app..., program_history) for app in new_applicants]
    past_applicants = read_applicant_data(joinpath(@__DIR__, "data", "applicantdata.csv"); program_history)
    # The data was set up to be symmetric except for date
    od = offerdata(past_applicants, program_history)
    @test od["NS"] == od["CB"] == (18, 160)
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
