ratio0(a, b) = iszero(a) ? a/oneunit(b) : a/b

function aggregate(facrec::FacultyRecord, mergepairs, covered=Set{String}())
    empty!(covered)
    progs = String[]
    for prog in facrec.programs
        sprog = substitute(prog, mergepairs)
        sprog ∈ covered || push!(progs, sprog)
        push!(covered, sprog)
    end
    service = Dict{String,Service}()
    for (prog, s) in facrec.service
        aggregate!(service, substitute(prog, mergepairs), s)
    end
    return FacultyRecord(facrec.start, progs, sort(collect(service); by=first))
end

function aggregate!(service::AbstractDict{String,Service}, sprog::AbstractString, s)
    service[sprog] = get!(Service, service, sprog) + s
    return service
end
function aggregate!(service::AbstractDict{String,Service}, sprogs::AbstractVector{<:AbstractString}, s)
    n = length(sprogs)
    for sprog in sprogs
        service[sprog] = get!(Service, service, sprog) + s/n
    end
    return service
end

"""
    facrecsnew = aggregate(facrecs::ListPairs{<:AbstractString,FacultyRecord}, mergepairs)

Aggregate faculty records, merging program `from => to` pairs from `mergepairs`.
"""
function aggregate(facrecs::ListPairs{<:AbstractString,FacultyRecord}, mergepairs)
    covered = Set{String}()
    return [name=>aggregate(facrec, mergepairs, covered) for (name, facrec) in facrecs]
end
