module AdmitConfiguration

using Dates
using UUIDs
using Missings
using ODBC
using Preferences
using Requires

# constants
export program_lookups, program_abbreviations, program_range, program_substitutions
# functions
export addprogram, delprogram, validateprogram, setprograms
export substitute, merge_program_range!
# SQL
export setdsn, connectdsn

const program_lookups = Dict{String,String}()
const program_abbreviations = Set{String}()
const program_range = Dict{String,UnitRange{Int}}()
const program_substitutions = Dict{String,Vector{String}}()
const sql_dsn = Ref{String}()
# const sql_connect = Ref{String}()

"""
    addprogram(abbrv::AbstractString)

Dynamically add a new program with abbreviation `abbrv`.

This is primarily used for writing tests; most users should use [`setprograms`](@ref) instead.
"""
function addprogram(abbrv::AbstractString)
    push!(program_abbreviations, abbrv)
    program_range[abbrv] = 0:year(today())
    return
end

"""
    delprogram(abbrv::AbstractString)

Dynamically delete the program with abbreviation `abbrv`.

This is primarily used for writing tests; most users should use [`setprograms`](@ref) instead.
"""
function delprogram(abbrv::AbstractString)
    delete!(program_abbreviations, abbrv)
    delete!(program_range, abbrv)
    return
end

"""
    prog = validateprogram(program::AbstractString)

Return the abbreviation `prog` from either a valid abbreviation or valid long-form program name `program`.
An error is thrown if the program is not recognized.

See [`setprograms`](@ref) to configure your local programs, or [`addprogram`](@ref) and [`delprogram`](@ref)
to configure them dynamically.
"""
validateprogram(program::AbstractString) = program ∈ program_abbreviations ? String(program) : program_lookups[program]

"""
    setprograms(filename; force=false)

Configure your local programs, given a CSV file `filename` of the format in `examples/WashU.csv`.
(You can create such files with a spreadsheet program, exporting the table in "Comma separated value" format.)
The minimum requirement is the `Abbreviation` column, which must contain the list of all programs
in "short-form" name. Use `ProgramName` if you want a long-form name, especially if you use a SQL database
which sometimes uses that name.

`SeasonStart`, `SeasonEnd`, `MergeTo`, and `SplitFrom` can be used to track changes in your programs over time;
this can be relevant because historical data is used to forecast matriculation probability (for `Admit.jl`) and
faculty service (for `AdmissionTargets.jl`).
"Season" refers to the year for final acceptance of an offer of admission, e.g., a deadline of April 15, 2013 would be season 2013.
`SeasonStart` should contain the first season in which a program admitted applicants; `SeasonEnd` should contain the last
season (if applicable) in which a program admitted applicants. If a defunct program merged into a newer one, set
the `MergeTo` field as the name of the newer program; if a current program was created from a previous one, set the
`SplitFrom` field. If a newly-created program has no clear heritage, just leave these blank (but no prior historical data
will be available).

If you're re-setting the configuration from an existing one, use `force=true`.

!!! warning
    You need to load the CSV package (`using CSV`) for `setprograms` to be available. See the AdmissionSuite
    web documentation for more information.
"""
function setprograms
    # This is loaded conditionally, see `__init__` and `setprograms.jl`
end

# low-level internal utilities
function substitute(prog, subs)
    for (from, to) in subs
        prog == from && return to
    end
    return prog
end

function merge_program_range!(progrange, subs)
    for (from, tos) in subs
        rfrom = progrange[from]
        for to in tos
            rto = progrange[to]
            progrange[to] = min(minimum(rfrom), minimum(rto)):maximum(rto)
        end
    end
    for (from, _) in subs
        delete!(progrange, from)
    end
    return progrange
end

"""
    setdsn(name)

Configure a Data Source `name` for a SQL database
"""
function setdsn(name::AbstractString)
    @set_preferences!("sql_dsn" => name)
end

"""
    setconnect(str)

Configure SQL database access via a "connect" string `str`.

!!! warning
    Omit your UID (user name) and PWD (password) from `str`, otherwise it gets stored in plain-text and is a security risk.
"""
function setconnect(str::AbstractString)
    @set_preferences!("sql_connect" => str)
end

include("sql.jl")

function __init__()
    @require CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b" include("setprograms.jl")

    loadprefs()
end

function loadprefs()
    onloadpath = suitedir ∈ LOAD_PATH
    if !onloadpath
        push!(LOAD_PATH, suitedir)
    end

    plook = @load_preference("program_lookups")
    plook !== nothing && merge!(program_lookups, plook)
    pabv = @load_preference("program_abbreviations")
    pabv !== nothing && for abbrv in pabv
        push!(program_abbreviations, abbrv)
    end
    prng = @load_preference("program_range")
    prng !== nothing && for (name, rng) in prng
        program_range[name] = rng["start"]:rng["stop"]
    end
    psubs = @load_preference("program_substitutions")
    psubs !== nothing && merge!(program_substitutions, psubs)
    pdsn = @load_preference("sql_dsn")
    pdsn !== nothing && (sql_dsn[] = pdsn)
    # pconnect = @load_preference("sql_connect")
    # pconnect !== nothing && sql_connect[] = pconnect

    if !onloadpath
        pop!(LOAD_PATH)
    end
    return nothing
end

const suitedir = dirname(dirname(@__DIR__))

end
