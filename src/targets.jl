"""
    fiis = faculty_involvement(faculty_engagement; annualthresh=1, yr=year(today()), normalize::Bool=true)

Compute the Faculty Involvement Index (FII) for each program. `faculty_engagement` can be read via [`read_faculty_data`](@ref).
`annualthresh` is the threshold contribution per year for counting as "engaged"; 1 corresponds to performing a single Interview
or serving on 0.1 thesis committees. `yr` defines the year for which the engagement is computed, which affects how a faculty member's
contributions are weighed from the year in which they were granted DBBS membership.

`normalize=true` ensures "one faculty member, one vote" and is the recommended setting.
When `false`, a faculty who participates in multiple programs counts multiple times.
"""
function faculty_involvement(faculty_engagement; annualthresh=2, yr=year(today()), yrstart=yr-4, normalize::Bool=true, show::Union{Bool,String}=false, subst=default_program_subst, iswarn::Bool=true)
    fiis = Dict{String,Float32}()
    trange = yrstart:yr
    anyshow = isa(show, Bool) ? show : true
    qualified = Set{String}()
    for (facname, facrecord) in faculty_engagement
        facyrs = intersect(year(facrecord.start):yr, trange)
        thresh = annualthresh * length(facyrs)
        @assert thresh > 0
        tot = total(facrecord, facyrs)
        tot <= thresh && continue
        empty!(qualified)
        anyshow && print(facname, ": ")
        for programfi in facrecord.contributions
            progcor = subst(programfi.program)
            prev = get!(fiis, progcor, 0.0f0)
            if iswarn && iszero(program_time_weight(facyrs, programfi.program))
                @warn("$facname had a contribution that started before appointment date: $programfi")
            end
            if normalize
                fii = total(programfi, facyrs) / tot
                fiis[progcor] = prev + fii
            else
                fii = total(programfi, facyrs) > thresh
                if fii
                    if progcor ∉ qualified
                        fiis[progcor] = prev + fii
                        push!(qualified, progcor)
                    end
                end
            end
            anyshow && (isa(show, Bool) || programfi.program == show) && print(programfi, "=>", fii, " ")
        end
        anyshow && println()
    end
    return fiis
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
