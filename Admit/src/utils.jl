## Lower-level utilities

null(::Type{NTuple{N,T}}) where {N,T} = ntuple(_ -> zero(T), N)

"""
    normdate(t::Date, pdata::ProgramData)

Express `t` as a fraction of the gap between the first offer date and last decision date as stored in
`pdata` (see [`ProgramData`](@ref)).

# Examples

```jldoctest
julia> using Dates

julia> pd = ProgramData(firstofferdate=Date("2021-02-11"), lastdecisiondate=Date("2021-04-15"))
ProgramData(0, 0, missing, -1, Date("2021-02-11"), Date("2021-04-15"))

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

# For graduate programs, this is set nationally
# https://cgsnet.org/april-15-resolution
decisiondeadline(yr::Integer) = Date(yr, 4, 15)

applicant_score(rank::Int, pdata) = rank / pdata.napplicants
applicant_score(rank::Missing, pdata) = rank

season(date::Date) = year(date) + (month(date) > 7)
season(applicant::NormalizedApplicant) = applicant.season

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
        sprogs = substitute(pk.program, mergepairs)
        agg!(ph, pk, pd, sprogs)
    end
    return ph
end

function aggregate(yd::ListPairs{String, Outcome}, mergepairs)
    ph = Dict{String, Outcome}()
    for (prog, pd) in yd
        sprogs = substitute(prog, mergepairs)
        agg!(ph, prog, pd, sprogs)
    end
    return ph
end


agg!(ph, pk, pd, prog::AbstractString) = accum!(ph, makekey(pk, prog), pd)
function agg!(ph, pk, pd, progs::AbstractVector{<:AbstractString})
    n = length(progs)
    n == 1 && return agg!(ph, pk, pd, progs[1])
    for prog in progs
        agg!(ph, pk, pd/n, prog)
    end
    return ph
end

makekey(pk::ProgramKey, prog::AbstractString) = ProgramKey(prog, pk.season)
makekey(::AbstractString, prog::AbstractString) = prog

function accum!(ph, pk, pd)
    if !haskey(ph, pk)
        ph[pk] = pd
    else
        ph[pk] += pd
    end
    return ph
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
julia> program_candidates = Admit.generate_fake_candidates(program_history, 2021);

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
                                  program_offer_dates=nothing; decided::Union{Bool,AbstractFloat}=false, tnow::Date=today())
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
            if offerdate > tnow
                accept = missing
            end
            NormalizedApplicant(; name=randstring(8)*" "*randstring(6),
                                  program=pk.program, rank=r,
                                  offerdate,
                                  accept,
                                  decidedate=isa(accept, Bool) ? rand(offerdate:Day(1):min(pd.lastdecisiondate, tnow)) : missing,
                                  program_history)
        end
    end
    return program_candidates
end
