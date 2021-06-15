## I/O

"""
    program_history = read_program_history(filename)

Read program history from a file. See "$(@__DIR__)/test/data/programdata.csv" for an example of the format.
"""
function read_program_history(filename::AbstractString)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename; types=Dict("year"=>Int, "program"=>String, "slots"=>Int, "nmatriculants"=>Int, "napplicants"=>Int, "lastdecisiondate"=>Date))
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

"""
    faculty_engagement = read_faculty_data(filename)

Read faculty training participation from a file. See "$(@__DIR__)/test/data/facultyinvolvement.csv" for an example of the format.
"""
function read_faculty_data(filename::AbstractString, args...)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename)
    return read_faculty_data(rows, args...)
end

function read_faculty_data(rows, programs=keys(program_lookups))
    function program_involvement(row, program)
        function int(n)
            n === missing && return 0
            isa(n, Int) && return n
            return parse(Int, n)
        end

        abbrv = validateprogram(program)
        ninterviews = int(get(row, Symbol("INTERVIEW $program"), 0))
        ncommittees = int(get(row, Symbol("THESIS CMTE $program"), 0))
        ninterviews == 0 && ncommittees == 0 && return nothing
        return FacultyInvolvement(abbrv, ninterviews, ncommittees)
    end
    function program_involvement(row)
        fis = FacultyInvolvement[]
        for program in programs
            fi = program_involvement(row, program)
            fi === nothing && continue
            push!(fis, fi)
        end
        return fis
    end

    dfmt = dateformat"mm/dd/yyyy"
    return Dict(map(rows) do row
        approval = row[Symbol("DBBS Approval Date")]
        approval === missing && @warn("no approval date for $(row.Faculty)")
        row.Faculty => FacultyRecord(approval === missing ? today() - Day(1) : Date(approval, dfmt), program_involvement(row))
    end)
end
