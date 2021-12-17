## Lower-level utilities

const program_lookups = Dict("Biochemistry" => "B",
                             "Biochemistry, Biophysics, and Structural Biology" => "BBSB",
                             "Biomedical Informatics and Data Science" => "BIDS",
                             "Cancer Biology" => "CB",
                             "Computational and Molecular Biophysics" => "CMB",
                             "Computational Biology" => "CompBio",
                             "Computational and Systems Biology" => "CSB",
                             "Developmental Biology" => "DB",
                             "Developmental, Regenerative and Stem Cell Biology" => "DRSCB",
                             "Evolution, Ecology and Population Biology" => "EEPB",
                             "Human and Statistical Genetics" => "HSG",
                             "Immunology" => "IMM",
                             "Molecular Biophysics" => "MB",
                             "Molecular Cell Biology" => "MCB",
                             "Molecular Genetics" => "MG",
                             "Molecular Genetics and Genomics" => "MGG",
                             "Molecular Microbiology and Microbial Pathogenesis" => "MMMP",
                             "Neurosciences" => "NS",
                             "Plant Biology" => "PB",
                             "Plant and Microbial Biosciences" => "PMB",
                             "Quantitative Human and Statistical Genetics" => "QHSG")
const program_abbrvs = Set(values(program_lookups))
# The range of years covered in the database
const program_range = Dict("B" => 2004:2017,
                           "BBSB" => 2018:typemax(Int),
                           "BIDS" => 2021:typemax(Int),
                           "CB" => 2020:typemax(Int),
                           "CMB" => 2010:2017,
                           "CSB" => 2010:typemax(Int),
                           "CompBio" => 2004:2009,
                           "DB" => 2004:2011,
                           "DRSCB" => 2012:typemax(Int),
                           "EEPB" => 2004:typemax(Int),
                           "HSG" => 2008:typemax(Int),
                           "IMM" => 2004:typemax(Int),
                           "MB" => 2004:2009,
                           "MCB" => 2004:typemax(Int),
                           "MG" => 2004:2007,
                           "MGG" => 2008:typemax(Int),
                           "MMMP" => 2004:typemax(Int),
                           "NS" => 2004:typemax(Int),
                           "PMB" => 2014:typemax(Int),
                           "PB" => 2004:2013,
                           "QHSG" => 2005:2007,
                           )
const default_program_substitutions = ["B" => "BBSB",
                                       "CMB" => "BBSB",
                                       "DB" => "DRSCB",
                                       "PB" => "PMB"]
function substitute(prog, subs)
    for (from, to) in subs
        prog == from && return to
    end
    return prog
end

function addprogram(prog)
    push!(program_abbrvs, prog)
    program_range[prog] = 0:year(today())
    return
end
function delprogram(prog)
    delete!(program_abbrvs, prog)
    delete!(program_range, prog)
    return
end
function merge_program_range!(progrange, subs)
    for (from, to) in subs
        rfrom, rto = progrange[from], progrange[to]
        progrange[to] = min(minimum(rfrom), minimum(rto)):maximum(rto)
        delete!(progrange, from)
    end
    return progrange
end

validateprogram(program::AbstractString) = program ∈ program_abbrvs ? String(program) : program_lookups[program]

date_or_missing(::Missing) = missing
date_or_missing(date::Date) = date
date_or_missing(date::AbstractString) = Date(date)

null(::Type{NTuple{N,T}}) where {N,T} = ntuple(_ -> zero(T), N)

"""
    normdate(t::Date, pdata::ProgramData)

Express `t` as a fraction of the gap between the first offer date and last decision date as stored in
`pdata` (see [`ProgramData`](@ref)).

# Examples

```jldoctest; setup=:(using AdmissionsSimulation)
julia> using Dates

julia> pd = ProgramData(firstofferdate=Date("2021-02-11"), lastdecisiondate=Date("2021-04-15"))
ProgramData(0, 0, 0, 0, Date("2021-02-11"), Date("2021-04-15"))

julia> normdate(Date("2021-02-11"), pd)
0.0f0

julia> normdate(Date("2021-04-15"), pd)
1.0f0

julia> normdate(Date("2021-03-15"), pd)
0.50793654f0

julia> normdate(Date("2021-01-01"), pd)    # dates prior to the first offer date are negatve
-0.6507937f0
```
"""
function normdate(t::Date, pdata::ProgramData)
    nt = (t - pdata.firstofferdate) / (pdata.lastdecisiondate - pdata.firstofferdate)
    return Float32(nt)
    # return clamp(Float32(nt), 0, 1)
end
normdate(t::Real, pdata) = t

applicant_score(rank::Int, pdata) = rank / pdata.napplicants
applicant_score(rank::Missing, pdata) = rank

season(date::Date) = year(date) + (month(date) > 7)
season(applicant::NormalizedApplicant) = applicant.season

# program_time_weight(trange::UnitRange, program::AbstractString) = length(intersect(trange, program_range[program]))/length(trange)

ratio0(a, b) = iszero(a) ? a/oneunit(b) : a/b
# total((program, fi)::Pair{String,Service}, trange::UnitRange) = ratio0(fi.ninterviews, program_time_weight(trange, program)) + 10*fi.ncommittees  # the factor of 10 credits the greater time commitment
# total(fr::FacultyRecord, trange::UnitRange) = sum(fr.service; init=0) do contrib
#     total(contrib, trange)
# end

function compute_target(program_history, season::Integer)
    target = 0
    for (pk, pd) in program_history
        pk.season == season || continue
        target += pd.target_corrected
    end
    return target
end
compute_target(program_history, tnow::Date) = compute_target(program_history, season(tnow))

## aggregate

"""
    proghist = aggregate(program_history::ListPairs{ProgramKey, ProgramData}, mergepairs)

Aggregate program history, merging program `from => to` pairs from `mergepairs`.
"""
function aggregate(program_history::ListPairs{ProgramKey, ProgramData}, mergepairs)
    ph = Dict{ProgramKey, ProgramData}()
    for (pk, pd) in program_history
        pksubs = ProgramKey(substitute(pk.program, mergepairs), pk.season)
        if !haskey(ph, pksubs)
            ph[pksubs] = pd
        else
            ph[pksubs] += pd
        end
    end
    return ph
end

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
        sprog = substitute(prog, mergepairs)
        service[sprog] = get!(Service, service, sprog) + s
    end
    return FacultyRecord(facrec.start, progs, sort(collect(service); by=first))
end

"""
    facrecsnew = aggregate(facrecs::ListPairs{<:AbstractString,FacultyRecord}, mergepairs)

Aggregate faculty records, merging program `from => to` pairs from `mergepairs`.
"""
function aggregate(facrecs::ListPairs{<:AbstractString,FacultyRecord}, mergepairs)
    covered = Set{String}()
    return [name=>aggregate(facrec, mergepairs, covered) for (name, facrec) in facrecs]
end

"""
    program_candidates = generate_fake_candidates(program_history, season::Integer, program_offer_dates=nothing)

Generate fake candidates for each program, each ranked starting from 1. `season` is the year for which the offers
should be generated. Optionally provide `program_offer_dates`, a `program_name=>list_of_offer_dates` dictionary
which will be used to generate offer dates (by default set to the `firstofferdate` in `program_history`).
Unless `σt` is quite small in the matching function, adding additional offer dates (e.g., for multiple interview dates)
may not change the outcome substantially.

On output, `program_candidates` is a `Dict(program1=>[applicant1a, applicant1b, ...], ...)` storing the fake applicants
per program in rank order. See [`initial_offers!`](@ref).

# Example

This calculates the number of initial offers per program:

```
julia> program_candidates = AdmissionsSimulation.generate_fake_candidates(program_history, 2021);

julia> program_offers = initial_offers!(fmatch, program_candidates, past_applicants, Date("2021-01-01"); program_history);

julia> noffers = sort([prog => length(list) for (prog, list) in program_offers]; by=first)
13-element Vector{Pair{String, Int64}}:
  "BBSB" => 16
  "BIDS" => 9
    "CB" => 13
   "CSB" => 14
 "DRSCB" => 14
  "EEPB" => 12
   "HSG" => 9
   "IMM" => 16
   "MCB" => 16
   "MGG" => 18
  "MMMP" => 18
    "NS" => 31
   "PMB" => 14
```
"""
function generate_fake_candidates(program_history::ListPairs{ProgramKey,ProgramData}, season::Integer,
                                  program_offer_dates=nothing; decided::Union{Bool,AbstractFloat}=false)
    randchoice(ds) = isa(ds, Date) ? ds : rand(ds)::Date

    program_candidates = Dict{String,Vector{NormalizedApplicant}}()
    for (pk, pd) in program_history
        pk.season == season || continue
        program_candidates[pk.program] = map(1:pd.napplicants) do r
            if decided isa Bool
                accept = decided ? rand(Bool) : missing
            else
                accept = rand() < decided ? rand(Bool) : missing
            end
            offerdate = program_offer_dates === nothing ? pd.firstofferdate : randchoice(get(program_offer_dates, pk.program, pd.firstofferdate))
            NormalizedApplicant(; name=randstring(8)*" "*randstring(6),
                                  program=pk.program, rank=r,
                                  offerdate,
                                  accept,
                                  decidedate=isa(accept, Bool) ? rand(offerdate:Day(1):pd.lastdecisiondate) : missing,
                                  program_history)
        end
    end
    return program_candidates
end
