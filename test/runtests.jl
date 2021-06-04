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
    past_applicants = [NormalizedApplicant(app; program_history) for app in past_applicants]

    applicant = NormalizedApplicant((program="NS", rank=11, offerdate=Date("2021-01-13")); program_history)

    # A match function that heavily weights normalized rank
    fmatch = match_function(matchprogram=false, σr=0.01, σt=Inf)
    like = @inferred(match_likelihood(fmatch, past_applicants, applicant, 0.0))
    @test like[3] > like[1] > like[2]
    @test matriculation_probability(like, past_applicants) > 0.95
    clike = cumsum(like)
    s = [select_applicant(clike, past_applicants) for i = 1:100]
    sc = first.(sort(collect(pairs(countby(s))); by=last))
    @test sc[end].program == "CB"    # best match is to rank 11/302 ≈ 6/160
    @test sc[end-1].program == "NS" && sc[end-1].normrank == Float32(7/302)

    # A match function that heavily weights offer date
    fmatch = match_function(matchprogram=false, σr=Inf, σt=0.3)
    like = match_likelihood(fmatch, past_applicants, applicant, 0.0)
    @test like[1] == like[2] == 1
    @test like[1] > like[3]
    @test 0.48 < matriculation_probability(like, past_applicants) < 0.52

    # Require program-specific matching
    fmatch = match_function(matchprogram=true, σr=0.01, σt=Inf)
    like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-01-13"); program_history)
    @test like[1] > like[2]
    @test like[3] == 0

    # Excluding applicants who had already decided at this point in the season
    fmatch = match_function(matchprogram=true, σr=0.01, σt=Inf)
    like = match_likelihood(fmatch, past_applicants, applicant, Date("2021-04-01"); program_history)
    @test like[2] > 0
    @test like[1] == like[3] == 0

    # I/O
    program_history = read_program_history(joinpath(@__DIR__, "data", "programdata.csv"))
    new_applicants = [(program="NS", rank=7, offerdate=Date("2021-01-13")),
                      (program="NS", rank=3, offerdate=Date("2021-01-13")),
                      (program="CB", rank=6, offerdate=Date("2021-03-25")),
    ]
    new_applicants = [NormalizedApplicant(app; program_history) for app in new_applicants]
    past_applicants = read_applicant_data(joinpath(@__DIR__, "data", "applicantdata.csv"); program_history)
    fmatch = match_function(matchprogram=true, σr=0.05, σt=0.5)
    pmatric = map(new_applicants) do applicant
        like = match_likelihood(fmatch, past_applicants, applicant, 0.0)
        matriculation_probability(like, past_applicants)
    end
    @test all(x -> 0 <= x <= 1, pmatric)
end
