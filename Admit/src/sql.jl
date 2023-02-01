"""
    apps = query_applicants(conn; deduplicate=false)

Fetch all applicants (past and present) from the database using connection `conn`.
`apps` is a DataFrame. Configure the SELECT statement using [`set_sql_queries`](@ref).

If your database contains multiple entries for each applicant, set `deduplicate=true`
and see the configuration needed for [`keep_final_records`](@ref).
"""
function query_applicants(conn; deduplicate::Bool=false)
    apps = DBInterface.execute(conn, AdmitConfiguration.sql_queries["applicants"]) |> DataFrame
    if deduplicate
        apps = keep_final_records(apps)
    end
    return apps
end

"""
    progdata = query_programs(conn)

Fetch program targets and other information from the database using connection `conn`.
`progdata` is a DataFrame. Configure the SELECT statement using [`set_sql_queries`](@ref).

If your database contains multiple entries for each applicant, set `deduplicate=true`
and see the configuration needed for [`keep_final_records`](@ref).
"""
function query_programs(conn)
    return DBInterface.execute(conn, AdmitConfiguration.sql_queries["programs"]) |> DataFrame
end

function season(row::DataFrameRow, tablename::String)  # tablename ∈ ("app", "prog")
    colname = get(column_configuration, tablename * " season", nothing)
    if colname !== nothing
        return getproperty(row, colname)
    end
    # If this next line errors, check whether "app season" or "prog season" can be added to `column_configuration`
    return season(todate(getproperty(row, column_configuration["offer date"])))
end

"""
    keep_final_records(apps)

De-duplicate applicant entries retrieved from the database. For each (`season`, `name`)
combination, this keeps only the most recently updated entry.

This requires that you define a `when_updated(row)` function for your database format,
see [`AdmitConfiguration.set_local_functions`](@ref).
"""
function keep_final_records(apps)
    appidx = Dict{Tuple{Int,String},Int}()   # (season, name) => index
    for (i, row) in enumerate(eachrow(apps))
        name = getproperty(row, column_configuration["name"])
        yr = season(row, "app")
        key = (yr, name)
        if !haskey(appidx, key)
            appidx[key] = i
        else
            j = appidx[key]
            dti = when_updated(row)
            dtj = when_updated(apps[j,:])
            if dti > dtj
                appidx[key] = i
            end
        end
    end
    idx = sort!(collect(values(appidx)))  # the `sort!` preserves order, though it is unlikely to be meaningful
    return apps[idx,:]
end

function parse_applicant_row(row, column_configuration)
    name = getproperty(row, column_configuration["name"])
    prog = try
        validateprogram(getproperty(row, column_configuration["app program"]))
    catch
        return name
    end
    offerdate = todate_or_missing(getproperty(row, column_configuration["offer date"]))
    if !ismissing(offerdate)
        accept = try getaccept(row) catch _ getproperty(row, column_configuration["accept"]) end
        choicedate = try getdecidedate(row) catch _ todate_or_missing(getproperty(row, column_configuration["decide date"])) end
        rankcol = get(column_configuration, "rank", missing)
        rank = rankcol === missing || !haskey(row, rankcol) ? missing : getproperty(row, rankcol)
        return name, prog, offerdate, accept, choicedate, rank
    end
    return name, prog, getproperty(row, column_configuration["app season"])
end

function parse_program_row(row, column_configuration)
    prog = try
        validateprogram(getproperty(row, column_configuration["prog program"]))
    catch
        return nothing
    end
    _season = getproperty(row, column_configuration["prog season"])

    slots = -1
    slotscol = get(column_configuration, "slots", nothing)
    if slotscol !== nothing && haskey(row, slotscol)
        slots = getproperty(row, slotscol)
    end

    napplicants = -1
    nappcol = get(column_configuration, "napplicants", nothing)
    if nappcol !== nothing && haskey(row, nappcol)
        napplicants = getproperty(row, nappcol)
    end

    nmatriculants = missing
    nmatcol = get(column_configuration, "nmatriculants", nothing)
    if nmatcol !== nothing && haskey(row, nmatcol)
        nmatriculants = getproperty(row, nmatcol)
    end
    return ProgramKey(prog, _season) => (slots=slots, napplicants=napplicants, nmatriculants=nmatriculants)
end

"""
    program_metadata = parse_programs(programs::DataFrame)

Extract program metadata:

- target number of matriculants, aka "slots"
- total number of applicants
- total number of matriculants (i.e., number who accepted the offer of admission)
"""
function parse_programs(programs::DataFrame)
    return Dict(Iterators.filter(!=(nothing), parse_program_row(row, AdmitConfiguration.column_configuration) for row in eachrow(programs)))
end

struct DummyMetadata end
Base.getindex(::DummyMetadata, pk::ProgramKey) = ()
Base.get(::DummyMetadata, pk::ProgramKey, val) = val
Base.iterate(::DummyMetadata) = nothing

"""
    program_history = extract_program_history(applicants)
    program_history = extract_program_history(applicants, program_metadata)

Assemble the necessary `program_history` from `applicants` and external `program_metadata`.
`applicants` is parsed to identify the date of the first offer for each `ProgramKey(program, season)`
combination. The remaining data come from `program_metadata`, which can be obtained from [`parse_programs`](@ref).
"""
function extract_program_history(applicants::DataFrame, program_metadata=DummyMetadata())
    firstoffer = Dict{ProgramKey,Date}()
    havefull = false
    for row in eachrow(applicants)
        ret = parse_applicant_row(row, AdmitConfiguration.column_configuration)
        if length(ret) == 6
            havefull = true
            name, prog, offerdate, accept, choicedate, rank = ret
            pk = ProgramKey(prog, season(offerdate))
            firstoffer[pk] = min(get(firstoffer, pk, typemax(Date)), offerdate)
        elseif length(ret) == 3
            name, prog, _season = ret
            pk = ProgramKey(prog, _season)
            get!(firstoffer, pk, typemax(Date))
        end
    end
    havefull || error("did not extract any full rows; check whether dates are in the format `$(AdmitConfiguration.date_fmt[])` expected by `AdmitConfiguration.date_fmt`")
    keys_with_sentinel = ProgramKey[]
    for (pk, d) in firstoffer
        if d == typemax(Date)
            push!(keys_with_sentinel, pk)
        end
    end
    if !isempty(keys_with_sentinel)
        sort!(keys_with_sentinel)
        @warn "No first offer date identified for $keys_with_sentinel"
    end
    out = Dict(pk => programdata(fo; get(program_metadata, pk, ())...) for (pk, fo) in firstoffer)
    # Add in any programs that have not yet made an offer in the current year
    for (pk, meta) in program_metadata
        if !haskey(out, pk)
            out[pk] = programdata(typemax(Date); meta...)
        end
    end
    return out
end

programdata(firstofferdate::Date; lastdecisiondate=decisiondeadline(season(firstofferdate)), kwargs...) =
    ProgramData(; firstofferdate, lastdecisiondate, kwargs...)
programdata(season::Integer; lastdecisiondate=decisiondeadline(season), kwargs...) =
    ProgramData(; lastdecisiondate, kwargs...)

function parse_applicants(applicants::DataFrame, program_history)
    napplicants = NormalizedApplicant[]
    for row in eachrow(applicants)
        ret = parse_applicant_row(row, AdmitConfiguration.column_configuration)
        if length(ret) == 6
            name, program, offerdate, accept, decidedate, rank = ret
            push!(napplicants, NormalizedApplicant(; name, program, offerdate, decidedate, accept, program_history, rank))
        elseif length(ret) == 3
            name, program, season = ret
            push!(napplicants, NormalizedApplicant(; name, program, season, program_history))
        end
    end
    return napplicants
end

"""
    applicants, program_history = parse_database(conn)

Extract the `applicants` and `program_history` from the database.
"""
function parse_database(conn; kwargs...)
    apps = query_applicants(conn; kwargs...)
    program_metadata = parse_programs(query_programs(conn))
    program_history = extract_program_history(apps, program_metadata)
    return parse_applicants(apps, program_history), program_history
end
