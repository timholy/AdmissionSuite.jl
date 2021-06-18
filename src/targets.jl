## Affiliation-based measures

"""
    naffil = faculty_affiliations(facrecs, scheme)

Compute the number of affiliations per program. `facrecs` is a list of `facultyname::String => facrec::FacultyRecord`
pairs containing details about the affiliations of each faculty member (see [`FacultyRecord`](@ref)).
`facrecs` can be read via [`read_faculty_data`](@ref).

`scheme` controls the weighting of affiliations for faculty members with more than one affiliation:
- `:primary`: count only the faculty member's primary affiliation (one vote/faculty)
- `:all`: count all affiliations (multiple votes/faculty depending on the number of affiliations)
- `:normalized`: one vote per faculty, spread equally among all that faculty member's affiliations
- `:weighted`: one vote per faculty, with decreasing weight. For a faculty member with 3 affiliations,
  they would be assigned a ratio of 3 to 2 to 1.  Hence the primary program would get 3/6=0.5,
  secondary 2/6=0.33, and tertiary 1/6=0.17.
"""
function faculty_affiliations(facrecs::ListPairs{String,FacultyRecord}, scheme::Symbol=:normalized)
    naffil = Dict{String,Float32}()
    for (_, facrec) in facrecs
        add_affiliations!(naffil, facrec, scheme)
    end
    return naffil
end

# helper functions
function add_affiliations!(naffil, facrec::FacultyRecord, scheme::Symbol)
    if scheme === :primary
        add_affiliation!(naffil, facrec, 1, 1)
    elseif scheme === :all
        n = length(facrec.programs)
        for i = 1:n
            add_affiliation!(naffil, facrec, i, 1)
        end
    elseif scheme === :normalized
        n = length(facrec.programs)
        for i = 1:n
            add_affiliation!(naffil, facrec, i, 1/n)
        end
    elseif scheme === :weighted
        n = length(facrec.programs)
        weights = n:-1:1
        W = sum(weights)
        for i = 1:n
            add_affiliation!(naffil, facrec, i, weights[i]/W)
        end
    else
        throw(ArgumentError("scheme $scheme not recognized"))
    end
    return naffil
end

function add_affiliation!(naffil, facrec::FacultyRecord, idx, weight=1)
    length(facrec.programs) < idx && return naffil
    program = facrec.programs[idx]
    naffil[program] = get(naffil, program, 0) + weight
    return naffil
end

## Effort-based measures

"""
    progsvc = program_service(facrecs)

Compute the total service for each program. `progsvc` is a `Dict(progname => ::Service)`.
"""
function program_service(facrecs::ListPairs{String,FacultyRecord})
    progsvc = Dict{String,Service}()
    for (_, facrec) in facrecs
        for (prog, s) in facrec.service
            progsvc[prog] = get(progsvc, prog, Service()) + s
        end
    end
    return progsvc
end

"""
    sc = calibrate_service(progsvc, yrthresh = <7 years ago today>)

Calculate an equivalence between different forms of service.
This is to handle the fact that young programs don't provide opportunities for service in the form of thesis commmittees.
`progsvc` is from [`program-service`](@ref), and `yrthresh` selects "old" programs (ones that existed prior to `yrthresh`)
useful for calibration.

`sc` allows a calculation of total service based on the maximum score computed from interviews or from committees.
"""
function calibrate_service(progsvc::ListPairs{String,Service}, yrthresh = year(today())-7)
    progrange = merge_program_range!(copy(program_range), default_program_substitutions)
    progsvc = sort(collect(progsvc); by=first)
    isold = [minimum(progrange[prog]) < yrthresh for (prog, _) in progsvc]
    progsvc_old = progsvc[isold]
    ninterviews = map(pr->pr.second.ninterviews, progsvc_old)
    ncommittees = map(pr->pr.second.ncommittees, progsvc_old)
    # Calculate the predicted number of committees from the number of interviews
    c_per_i = ninterviews \ ncommittees
    # Define a "service unit" as max(c_per_i * i, c)
    svcunit = max.(c_per_i * ninterviews, ncommittees)
    # Regress "service time" against "service unit"
    svctime = (total ∘ last).(progsvc_old)
    t_per_u = svcunit \ svctime
    return ServiceCalibration(c_per_i, t_per_u)
end
calibrate_service(facrecs::ListPairs{String,FacultyRecord}, args...) =
    calibrate_service(program_service(facrecs), args...)

"""
    faculty, programs, E = faculty_effort(facrecs, daterange::AbstractRange; sc=nothing, progrange=<default>)

Use `facrecs`, a list of `facultyname::String => facrec::FacultyRecord` pairs, to estimate the average annual effort (in hours)
contributed in the forms of service tracked in [`Service`](@ref). See [`FacultyRecord`](@ref) and [`read_faculty_data`](@ref).
`daterange` specifies the time span covered by `facrecs`; it could be a `Date` range or something like `2016:2020` to indicate
a span in calendar years.
The optional `sc` allows you to supply a service calibration, see [`calibrate_service`](@ref).
`progyears` lets you supply a `Dict(progname => yearrange)` specifying the duration of existence of each program;
the default effectively assumes you've called [`aggregate`](@ref) on `facrecs` to consolidate defunct programs into their
modern equivalents.

On output, `E` is a `length(faculty)`-by-`length(programs)` matrix, where `E[j,i]` measures the average annual effort committed
by faculty member `faculty[j]` to `programs[i]`.
"""
function faculty_effort(facrecs::ListPairs{String,FacultyRecord},
                        daterange::AbstractRange{<:Union{Integer,Date}};
                        sc=nothing,
                        progyears=merge_program_range!(copy(program_range), default_program_substitutions),
                        finaldate=today())
    # Determine all the counted programs and all the counted faculty
    ufacs, uprogs = Set{String}(), Set{String}()
    for (key, facrec) in facrecs
        push!(ufacs, key)
        for (prog, _) in facrec.service
            push!(uprogs, prog)
        end
    end
    uprogs, ufacs = sort(collect(uprogs)), sort(collect(ufacs))
    proglkup = Dict(zip(uprogs, 1:length(uprogs)))
    faclkup = Dict(zip(ufacs, 1:length(ufacs)))
    ndays = eltype(daterange) === Date ? length(daterange) : length(daterange) * 365
    thisyear = year(finaldate)
    dayrange = eltype(daterange) === Date ? daterange : (Date(minimum(daterange), 1, 1):Day(1):Date(min(thisyear, maximum(daterange)), 12, 31))
    progdays = Dict(name => Date(minimum(yrrng), 1, 1):Day(1):Date(min(thisyear, maximum(yrrng)), 12, 31) for (name, yrrng) in progyears)
    # Tally as a matrix
    E = zeros(Float32, length(ufacs), length(uprogs))
    for (key, facrec) in facrecs
        j = faclkup[key]
        daysfac = intersect(facrec.start:Day(1):finaldate, dayrange)
        for (prog, fi) in facrec.service
            thisprogdays = intersect(daysfac, progdays[prog])
            E[j, proglkup[prog]] += (sc === nothing ? total(fi) : total(fi, sc)) / (length(thisprogdays)/365)
        end
    end
    return ufacs, uprogs, E
end

"""
    f = faculty_involvement(E::AbstractMatrix; scheme=:normeffort, annualthresh=2, M=size(E,1))

Compute the effective number of faculty `f[i]` involved in program `i`, based on annual effort `E` as computed
by [`faculty_effort`](@ref). `annualthresh` is the number of hours that must be exceeded in order to qualify
as a contributing faculty member.

There are three schemes available:
- `:thresheffort`: `f[i]` gets a +1 contribution from faculty member `j` if `j` exceeded `annualthresh` in that program.
  (This allows one faculty member to count multiple times.)
- `:normeffort` (the default): for each faculty member who's total service hours across all programs exceeds `annualthresh`,
  distribute a total of one vote in proportion to service per program.
- `:effortshare`: calculate the average service per faculty member (`M` faculty members total) for each program.
  If a faculty member exceeded this threshold for `k` programs, add `1/k` to each. `annualthresh` plays no role here.
"""
function faculty_involvement(E::AbstractMatrix; scheme=:normeffort, annualthresh=2, M=size(E,1))
    scheme === :thresheffort && return vec(sum(E .> annualthresh; dims=1))
    if scheme === :normeffort
        Esum2 = sum(E; dims=2)     # total effort by faculty member
        contributes = Esum2 .> annualthresh
        return vec(sum(ratio0.(E .* contributes, Esum2); dims=1))
    end
    if scheme === :effortshare
        θs = sum(E; dims=1) / M    # the average workload per faculty
        Ethresh = E .> θs
        Enorm = sum(Ethresh; dims=2)
        return vec(sum(ratio0.(Ethresh, Enorm) ; dims=1))
    end
    throw(ArgumentError("scheme $scheme unknown"))
end

"""
    targets(program_applicants, fiis, N)

Compute the target number of matriculants for each program. `program_applicants` is a collection of `program => napplicants`
pairs; `fiis` is a collection of `program => FII` scores (see [`faculty_involvement`](@ref)).
`N` is the total number of matriculants across all programs.

Each program gets weighted by the geometric mean of the # of applicants and FII.
"""
function targets(program_applicants, fiis, N)
    weights = Float32[]
    for (program, napplicants) in program_applicants
        push!(weights, sqrt(napplicants * fiis[program]))
    end
    W = sum(weights)
    tgts = Dict{String,Float32}()
    for ((program, napplicants), w) in zip(program_applicants, weights)
        tgts[program] = N*w/W
    end
    return tgts
end

function targets(program_applicants, fiis, N, per_program_gift)
    weights = Float32[]
    for (program, napplicants) in program_applicants
        push!(weights, sqrt(napplicants * fiis[program]))
    end
    W = sum(weights)
    tgts = Dict{String,Float32}()
    Nsave = length(program_applicants) * per_program_gift
    for ((program, napplicants), w) in zip(program_applicants, weights)
        tgts[program] = per_program_gift + (N-Nsave)*w/W
    end
    return tgts
end
