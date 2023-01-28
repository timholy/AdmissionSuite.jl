## I/O

# These are quite specific to particular CSV formats and may need adaptation for changes

"""
    program_history = read_program_history(filename)

Read program history from a file. See "$(@__DIR__)/test/data/programdata.csv" for an example of the format.
"""
function read_program_history(filename::AbstractString)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("year"=>Int, "program"=>String, "slots"=>Int, "nmatriculants"=>Int, "napplicants"=>Int, "lastdecisiondate"=>Date), validate=false)
    try
        return Dict(map(rows) do row
            ProgramKey(season=row.year, program=row.program) => ProgramData(slots=row.slots,
                                                                            nmatriculants=get(row, :nmatriculants, missing),
                                                                            napplicants=row.napplicants,
                                                                            firstofferdate=date_or_missing(row.firstofferdate),
                                                                            lastdecisiondate=row.lastdecisiondate)
        end)
    catch
        error("the headers must be year (Int), program (String), slots (Int), napplicants (Int), firstofferdate (Date or missing), lastdecisiondate (Date). The case must match.")
    end
end

"""
    past_applicants = read_applicant_data(filename; program_history)

Read past applicant data from a file. See "$(@__DIR__)/test/data/applicantdata.csv" for an example of the format.
"""
function read_applicant_data(filename::AbstractString; program_history)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("program"=>String,"rank"=>Int,"offerdate"=>Date,"decidedate"=>Date,"accept"=>Bool))
    try
        return [NormalizedApplicant(row; program_history) for row in rows]
    catch
        error("the headers must be program (String), rank (Int), offerdate (Date), decidedate (Date), accept (Bool). The case must match.")
    end
end
