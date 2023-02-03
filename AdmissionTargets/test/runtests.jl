# Tests for AdmissionTargets
# Passing these tests requires that you first configure the package
# See the AdmissionSuite/.github/workflows/CI.yml file for the needed configuration steps

using AdmissionTargets
using AdmitConfiguration
using Dates
using Test

@testset "AdmissionTargets.jl" begin
    @testset "Targets" begin
        dfmt = AdmitConfiguration.date_fmt[]
        AdmitConfiguration.date_fmt[] = DateFormat("mm/dd/yyyy")
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
        tgts3, _ = targets(program_applicants2, fiis, 6, 3; iswarn=false)
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
        facrecords = AdmissionTargets.aggregate(facrecords, AdmissionTargets.program_substitutions)
        progsvc = program_service(facrecords)
        @test progsvc["BIDS"] == Service(5, 0)
        @test progsvc["BBSB"] == Service(0, 3)
        @test progsvc["HSG"] == Service(11, 1)
        sc = calibrate_service(progsvc, 2019)
        @test sc == calibrate_service(facrecords, 2019)
        @test sc.c_per_i ≈ 1/11
        @test AdmissionTargets.total(Service(1, 0), sc)  ≈ 11.1/11
        @test AdmissionTargets.total(Service(0, 1), sc)  ≈ 11.1
        @test AdmissionTargets.total(Service(11, 1), sc) ≈ 11.1       # we use max over interview and committees
        @test AdmissionTargets.total(Service(12, 1), sc) ≈ 12/11 * 11.1
        facs, progs, E = faculty_effort(facrecords, Date("2021-01-01"):Day(1):Date("2021-05-31"); sc)
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
            AdmissionTargets.addprogram(prog)
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
        fiis = faculty_involvement(E; annualthresh=0.5)
        @test fiis == [1, 1, 1, 1]
        mergepairs = ["ProgA"=>"ProgABC", "ProgB"=>"ProgABC", "ProgC"=>"ProgABC"]
        AdmissionTargets.addprogram("ProgABC")
        aggrecs = AdmissionTargets.aggregate(facrecs, mergepairs)
        @test faculty_affiliations(aggrecs, :primary) == Dict("ProgD"=>1, "ProgABC"=>3)               # good
        @test faculty_affiliations(aggrecs, :all) == Dict("ProgD"=>3, "ProgABC"=>4)                   # bad
        @test faculty_affiliations(aggrecs, :normalized) == Dict("ProgD"=>1.5, "ProgABC"=>2.5)        # bad
        @test faculty_affiliations(aggrecs, :weighted) ==  Dict("ProgD"=>4/3.0f0, "ProgABC"=>8/3.0f0) # bad
        _, programsagg, Eagg = faculty_effort(aggrecs, 2020:2020)
        @test Eagg ≈ [3 0; 2 1; 2 1; 2 1]
        fiis = Dict(zip(programsagg, faculty_involvement(Eagg; annualthresh=0.5)))
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
            AdmissionTargets.delprogram(prog)
        end
        AdmissionTargets.delprogram("ProgABC")

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
        tgtsl = AdmissionTargets.targets_linear(napplicants, nfaculty, 17, 2)
        @test tgtsl["ProgA"] ≈ 2 + 5/17*13
        @test tgtsl["ProgB"] ≈ 2 + 12/17*13

        # Targets from applicants-only
        napplicants = Dict("ProgA"=>100, "ProgB"=>400)
        tgts = targets(napplicants, nothing, 10)
        @test tgts["ProgA"] ≈ 2
        @test tgts["ProgB"] ≈ 8
        tgts, p = targets(napplicants, nothing, 10, 4)
        @test tgts["ProgA"] ≈ 4
        @test tgts["ProgB"] ≈ 6
        @test_logs (:warn, "The following programs 'earned' less than one slot (give them notice): [\"ProgA\"]") targets(Dict("ProgA"=>1, "ProgB"=>11), nothing, 11, 2)
        AdmitConfiguration.date_fmt[] = dfmt
    end
end
