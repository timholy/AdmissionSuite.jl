# low-level internal utilities

"""
    addprogram(abbrv::AbstractString)

Dynamically add a new program with abbreviation `abbrv`.

This is primarily used for writing tests; most users should use [`set_programs`](@ref) instead.
"""
function addprogram(abbrv::AbstractString)
    push!(program_abbreviations, abbrv)
    program_range[abbrv] = 0:year(today())
    return
end

"""
    delprogram(abbrv::AbstractString)

Dynamically delete the program with abbreviation `abbrv`.

This is primarily used for writing tests; most users should use [`set_programs`](@ref) instead.
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

See [`set_programs`](@ref) to configure your local programs, or [`addprogram`](@ref) and [`delprogram`](@ref)
to configure them dynamically.
"""
validateprogram(program::AbstractString) = program ∈ program_abbreviations ? String(program) : program_lookups[program]


# substitute may return the input string or a list of strings, the caller must
# be prepared to handle either one
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

todate(d::Date) = d
todate(dt::DateTime) = Date(dt)
todate(datestr::AbstractString) = Date(datestr, date_fmt[])

function todate_or_missing(d)
    isa(d, AbstractString) && isempty(d) && return missing
    dp = tryparse(Date, d, date_fmt[])
    return dp === nothing ? missing : dp
end
# SQL can encode dates as integers: https://stackoverflow.com/questions/5505935/convert-from-datetime-to-int
todate_or_missing(d::Real) = Date("1899-12-30") + Day(trunc(d))
todate_or_missing(::Missing) = missing
