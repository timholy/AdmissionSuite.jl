module AdmitConfiguration

using Dates
using UUIDs
using Missings
using ODBC
using Preferences
using Requires

# constants
export program_lookups, program_abbreviations, program_range, program_substitutions, date_fmt, column_configuration
# utility functions
export addprogram, delprogram, validateprogram
export substitute, merge_program_range!
export todate, todate_or_missing
# Preference-setting
export set_programs, set_dsn, set_column_configuration, set_local_functions
# SQL
export connectdsn, set_sql_queries
# Parsing (local functions)
export getaccept, getdecidedate, when_updated

const suitedir = dirname(dirname(@__DIR__))
const program_lookups = Dict{String,String}()
const program_abbreviations = Set{String}()
const program_range = Dict{String,UnitRange{Int}}()
const program_substitutions = Dict{String,Vector{String}}()
const sql_dsn = Ref{String}()
const sql_queries = Dict{String,String}()
const date_fmt = Ref(dateformat"mm/dd/yyyy")
const local_functions = Ref{Union{String,Nothing}}()
const column_configuration = Dict{String,String}()

include("sql.jl")
include("local_function_stubs.jl")
# These must be loaded at compile time
local_functions[] = @load_preference("local_functions")
if isa(local_functions[], String)
    include(local_functions[])
end
include("utils.jl")

## Preferences

"""
    set_programs(filename; force=false)

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
    You need to load the CSV package (`using CSV`) for `set_programs` to be available. See the AdmissionSuite
    web documentation for more information.
"""
function set_programs
    # This is loaded conditionally, see `__init__` and `set_programs.jl`
end

"""
    set_dsn(name)

Configure a Data Source `name` for a SQL database
"""
function set_dsn(name::AbstractString)
    @set_preferences!("sql_dsn" => name)
end

"""
    set_sql_queries(; applicants = "SELECT * FROM ...", programs = "SELECT * FROM ...")

Configure the specific queries needed to obtain the applicants and program targets, respectively.
"..." needs to be specified for your local institution.
"""
function set_sql_queries(; applicants=nothing, programs=nothing)
    if applicants !== nothing
        sql_queries["applicants"] = applicants
    end
    if programs !== nothing
        sql_queries["programs"] = programs
    end
    @set_preferences!("sql_queries" => sql_queries)
end

"""
    set_local_functions(filename)

Configure custom functions used in parsing applicant tables. The following functions must be implemented:

- [`getaccept`](@ref)
- [`getdecidedate`](@ref)

The following are optional and only required for certain functionality:

- [`when_updated`](@ref)

Create these functions and save them to a file somewhere permanent on your system.
Then pass the filename to `set_local_functions` to register this file with AdmissionSuite.

See also: [`set_column_configuration`](@ref).
"""
function set_local_functions(str::AbstractString)
    filepath = abspath(str)
    if isfile(filepath)
        @set_preferences!("local_functions" => filepath)
    else
        error(filepath, " not found")
    end
end

"""
    set_column_configuration(stdname1 => dbcolname1, ...)

Configure the names of columns `dbcolname`s in your database so that standard properties can be extracted.
The properties that must be configured are:

Applicant table columns:

- "name": the name of the column that stores the applicant name
- "app program": the name of the column that stores the name of the program the applicant is being considered for admission in
- "offer date": the name of the column that stores the date at which an offer of admission was extended
- "app season" (optional): the name of the column that can be used to extract the application season (e.g., 2022)
  if an offer date is not available for a candidate

Program table columns:

- "prog program": the name of the column that stores the program name
- "prog season": the name of the column that can be used to extract the application season (e.g., 2022)
- "slots": the name of the column that stores the matriculation target for a program
- "napplicants" (optional): the name of the column that stores the number of applications received
- "nmatriculants" (optional): the name of the column that stores the number of applicants who accepted the offer of admission

# Example

```
set_column_configuration("name" => "Applicant Name", "app program" => "Program", "offer date" => "Acceptance Offered")
```
sets up the names of three columns in your database tables.

See also: [`set_local_functions`](@ref).
"""
function set_column_configuration(pairs...)
    function rekey((key, val))
        if key ∈ ("name", "app program", "offer date", "app season",
                  "prog program", "prog season", "slots", "napplicants", "nmatriculants")
            isa(val, AbstractString) || error(key, " must be a string")
        else
            error("unrecognized key ", key)
        end
        return key => val
    end
    pairs = map(rekey, pairs)
    for (key, val) in pairs
        column_configuration[key] = val
    end
    @set_preferences!("column_configuration" => column_configuration)
end

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

    cc = @load_preference("column_configuration")
    if cc !== nothing
        merge!(column_configuration, cc)
    end

    if !onloadpath
        pop!(LOAD_PATH)
    end
    return nothing
end

end
