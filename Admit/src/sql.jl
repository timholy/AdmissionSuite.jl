function query_applicants(conn)
    apps = DBInterface.execute(conn, "SELECT * FROM dbo.vw_interviewed_hold_outcome")|> DataFrame
    return keep_final_record(apps)
end

function keep_final_record(apps)
    appidx = Dict{Tuple{Int,String},Int}()
    for (i, row) in enumerate(eachrow(apps))
        if haskey(column_configuration, "season")
            yr = getproperty(row, column_configuration["season"])
        else
            yr = season(todate_or_missing(getproperty(row, column_configuration["offer date"])))
        end
        name = getproperty(row, column_configuration["name"])
        key = (yr, name)
        if !haskey(appidx, key)
            appidx[key] = i
        else
            j = appidx[key]
            dti = update_time(row)
            dtj = update_time(apps[j,:])
            if dti > dtj
                appidx[key] = i
            end
        end
    end
    idx = sort(collect(values(appidx)))
    return apps[idx,:]
end

update_time(row) = todate_or_missing(row."Stage Date")   # FIXME

function query_history(conn)
    return DBInterface.execute(conn, "SELECT * FROM dbo.vw_admit_targets")|> DataFrame
end

function parserow(row, column_configuration)
    name = getproperty(row, column_configuration["name"])
    prog = validateprogram(getproperty(row, column_configuration["program"]))
    offerdate = todate_or_missing(getproperty(row, column_configuration["offer date"]))
    if !ismissing(offerdate)
        accept = getaccept(row)
        choicedate = getdecidedate(row)
        return name, prog, offerdate, accept, choicedate
    end
    if haskey(column_configuration, "season")
        return name, prog, getproperty(row, column_configuration["season"])
    end
    return name, prog
end

struct DummyMetadata end
Base.getindex(::DummyMetadata, pk::ProgramKey) = ()

function extract_program_history(applicants::DataFrame, metadata=DummyMetadata())
    firstoffer = Dict{ProgramKey,Date}()
    for row in eachrow(applicants)
        ret = parserow(row, AdmitConfiguration.column_configuration)
        if length(ret) == 5
            name, prog, offerdate, accept, choicedate = ret
            pk = ProgramKey(prog, season(offerdate))
            firstoffer[pk] = min(get(firstoffer, pk, typemax(Date)), offerdate)
        elseif length(ret) == 3
            name, prog, _season = ret
            pk = ProgramKey(prog, _season)
            get!(firstoffer, pk, typemax(Date))
        end
    end
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
    # return firstoffer, metadata
    return Dict(pk => programdata(fo; get(metadata, pk, (slots=0,))...) for (pk, fo) in firstoffer)
end

programdata(firstofferdate::Date; kwargs...) = ProgramData(; firstofferdate, lastdecisiondate=decisiondeadline(season(firstofferdate)), kwargs...)
decisiondeadline(yr::Integer) = Date(yr, 4, 15)

function parse_applicants(applicants::DataFrame, program_history)
    napplicants = NormalizedApplicant[]
    for row in eachrow(applicants)
        ret = parserow(row, AdmitConfiguration.column_configuration)
        if length(ret) == 5
            name, program, offerdate, accept, decidedate = ret
            push!(napplicants, NormalizedApplicant(; name, program, offerdate, decidedate, accept, program_history))
        elseif length(ret) == 3
            name, program, season = ret
            push!(napplicants, NormalizedApplicant(; name, program, season, program_history))
        end
    end
    return napplicants
end

function parse_applicants(conn, metadata=DummyMetadata())
    df = query_applicants(conn)
    program_history = extract_program_history(df, metadata)
    return parse_applicants(df, program_history), program_history
end
