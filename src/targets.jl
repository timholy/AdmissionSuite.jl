"""
    aggregate!(faculty_engagement, mergepairs)

Aggregate data for defunct programs into their successors.
`faculty_engagement` can be read via [`read_faculty_data`](@ref).
`mergepairs` is a list of `from=>to` pairs of program abbreviations.

# Example

To aggregate the defunct Biochemistry ("B") and Computational and Molecular Biophysics ("CMB") programs
into their successor "BBSB", use
```julia
aggregate!(faculty_engagement, ["B"=>"BBSB", "CMB"=>"BBSB"])
```
"""
function aggregate!(faculty_engagement, mergepairs)
    todel = Int[]
    for (_, facrec) in faculty_engagement
        empty!(todel)
        for (from, to) in mergepairs
            for (i, contributioni) in enumerate(facrec.contributions)
                if contributioni.program == from
                    j = 1
                    contributionj = facrec.contributions[j]
                    while contributionj.program != to
                        j += 1
                        contributionj = checkbounds(Bool, facrec.contributions, j) ? facrec.contributions[j] : push!(facrec.contributions, FacultyInvolvement(to, 0, 0))[end]
                    end
                    contributionj += contributioni
                    push!(todel, i)
                end
            end
        end
        deleteat!(facrec.contributions, todel)
    end
    return faculty_engagement
end

"""
    fiis = faculty_involvement(faculty_engagement; annualthresh=1, yr=year(today()), normalize::Bool=true)

Compute the Faculty Involvement Index (FII) for each program. `faculty_engagement` can be read via [`read_faculty_data`](@ref).
`annualthresh` is the threshold contribution per year for counting as "engaged"; 1 corresponds to performing a single Interview
or serving on 0.1 thesis committees. `yr` defines the year for which the engagement is computed, which affects how a faculty member's
contributions are weighed from the year in which they were granted DBBS membership.

`normalize=true` ensures "one faculty member, one vote" and is the recommended setting.
When `false`, a faculty who participates in multiple programs counts multiple times.
"""
function faculty_involvement(faculty_engagement; annualthresh=1, yr=year(today()), normalize::Bool=true)
    fiis = Dict{String,Float32}()
    for (facname, facrecord) in faculty_engagement
        thresh = annualthresh * years(facrecord, yr)
        tot = total(facrecord)
        tot < thresh && continue
        for programfi in facrecord.contributions
            prev = get!(fiis, programfi.program, 0.0f0)
            fiis[programfi.program] = prev + (normalize ? total(programfi) / tot : total(programfi) >= thresh)
        end
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
