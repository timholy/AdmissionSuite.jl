
"""
facrecs = read_faculty_data(filename)

Read faculty training participation from a file. See "$(@__DIR__)/test/data/facultyinvolvement.csv" for an example of the format.
"""
function read_faculty_data(filename::AbstractString, args...)
    _, ext = splitext(filename)
    ext ∈ (".csv", ".tsv") || error("only CSV files may be read")
    rows = CSV.Rows(filename)
    return read_faculty_data(rows, args...)
end

function read_faculty_data(rows, full_program_names=sort(collect(keys(program_lookups))); iswarn::Bool=true)
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
        return abbrv => Service(ninterviews, ncommittees)
    end
    function program_involvement(row)
        fis = (eltype(fieldtype(FacultyRecord, :service)))[]
        for program in full_program_names
            fi = program_involvement(row, program)
            fi === nothing && continue
            push!(fis, fi)
        end
        return fis
    end
    function affiliations(row)
        programs = String[]
        for colname in ("Primary Program", "Secondary Program", "Tertiary Program")
            nextprog = get(row, Symbol(colname), missing)
            if nextprog !== missing && nextprog != "N/A"
                push!(programs, validateprogram(nextprog))
            end
        end
        return programs
    end

    result = Dict{String,FacultyRecord}()
    for (i, row) in enumerate(rows)
        isa(row.Faculty, AbstractString) || throw(ArgumentError("row $i: Faculty name must be a string"))
        approval = get(row, Symbol("DBBS Approval Date"), missing)
        if approval === missing
            iswarn && @warn("no approval date for $(row.Faculty) on row $i (omitting header from numbering)")
        else
            approval = match(r"(\d+/\d+/\d+)", approval).captures[1] # extract just the date (omit time)
        end
        result[row.Faculty] = FacultyRecord(approval === missing ? today() - Day(1) : Date(approval, date_fmt[]), affiliations(row), program_involvement(row))
    end
    return result
end
