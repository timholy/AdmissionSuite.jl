using Admit
using Admit.CSV
using DataFrames
using DBInterface
using Dates
using Test

struct FakeConn
    applicants::DataFrame
    programs::DataFrame
end

DBInterface.execute(conn::FakeConn, tablename::String) =
    tablename == "applicants" ? conn.applicants :
    tablename == "programs"   ? conn.programs   : error(tablename, " unrecognized")

@testset "fakedb" begin
    apps     = CSV.File(joinpath(@__DIR__, "data", "sql_applicant_table_with_duplicates.csv")) |> DataFrame
    programs = CSV.File(joinpath(@__DIR__, "data", "sql_program_table.csv")) |> DataFrame
    conn = FakeConn(apps, programs)

    # Save column_configuration and sql_queries before we modify them
    cc = copy(Admit.AdmitConfiguration.column_configuration)
    Admit.AdmitConfiguration.column_configuration["napplicants"] = "napp"
    Admit.AdmitConfiguration.column_configuration["nmatriculants"] = "nmatric"
    sqlq = copy(Admit.AdmitConfiguration.sql_queries)
    Admit.AdmitConfiguration.sql_queries["applicants"] = "applicants"
    Admit.AdmitConfiguration.sql_queries["programs"]   = "programs"

    try
        applicants, program_history = @test_logs (:warn, r"No first offer date identified for.*MGG.*PMB") parse_database(conn; deduplicate=true)

        for (prog, slots, nmatric, napp, fod) in zip(("MGG", "MMMP", "NS", "PMB"), (9, 11, 13, 15), (10, 12, 14, 16),
                                                    (100, 101, 102, 103), (typemax(Date), Date(2021, 2, 3), Date(2021, 2, 10), typemax(Date)))
            pd = program_history[ProgramKey(prog, 2021)]
            @test pd.target_corrected == slots
            @test pd.nmatriculants == nmatric
            @test pd.napplicants == napp
            @test pd.firstofferdate === fod
        end

        getapplicant(apps, name) = apps[findfirst(app->app.name==name, apps)]
        @test length(applicants) == 8
        for (name, prog, nod, accept, dd) in zip(("Last1, First1", "Last2, First2", "Last3, First3", "Last4, First4"),
                                                ("MGG", "MMMP", "NS", "PMB"),
                                                (missing, 0.0f0, 0.0f0, missing),
                                                (missing, false, true, missing),
                                                (missing, Date(2021, 3, 3), Date(2021, 4, 1), missing))
            app = applicants[findfirst(app->app.applicantdata.name==name, applicants)]
            @test app.program == prog
            @test app.season == 2021
            @test app.normofferdate === nod
            @test app.accept === accept
            if dd === missing
                @test app.normdecidedate === missing
            else
                fod = program_history[ProgramKey(prog, 2021)].firstofferdate
                @test app.normdecidedate == Float32((dd - fod)/(Date(2021, 4, 15) - fod))
            end
        end

        @async runweb(conn; deduplicate=true, tnow=Date(2021, 2, 28))
        if isinteractive()
            sleep(0.2)
            Base.prompt("hit enter to finish the tests")
        end
    finally
        # Restore the original column_configuration and sql_queries
        empty!(Admit.AdmitConfiguration.column_configuration)
        merge!(Admit.AdmitConfiguration.column_configuration, cc)
        empty!(Admit.AdmitConfiguration.sql_queries)
        merge!(Admit.AdmitConfiguration.sql_queries, sqlq)
    end
end
