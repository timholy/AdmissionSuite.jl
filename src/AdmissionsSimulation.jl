module AdmissionsSimulation

using Distributions
using Dates

export match_clikelihood, match_function, select_applicant

function match_clikelihood(fmatch::Function, past_applicants, applicant, tnow; program_history)
    pdata = program_data(applicant, program_history)
    match_clikelihood(fmatch, past_applicants, applicant, tnow, pdata)
end
function match_clikelihood(fmatch::Function, past_applicants, applicant, tnow, pdata)
    tnow = normdate(tnow, pdata)
    match_clikelihood(fmatch, past_applicants, applicant, tnow, pdata)
end
function match_clikelihood(fmatch::Function, past_applicants, applicant, tnow::Real, pdata)
    s = applicant_score(applicant.rank, pdata)
    toffer = normdate(applicant.offerdate, pdata)
    return cumsum([fmatch(applicant.program, tnow, toffer, s, app) for app in past_applicants])
end

function select_applicant(clikelihood, past_applicants)
    r = rand() * clikelihood[end]
    idx = searchsortedlast(clikelihood, r) + 1
    return past_applicants[idx]
end

function match_function(criteria; program_history=nothing)
    return function(program, tnow::Real, toffer::Real, score, app)
        # Include only applicants that hadn't decided by tnow
        pdata = program_data(app, program_history)
        tdecide = normdate(app.decidedate, pdata)
        tnow > tdecide && return 0.0
        # Check whether we need to match the program
        if criteria.matchprogram
            program !== app.program && return 0.0
        end
        app_toffer = normdate(app.offerdate, pdata)
        app_score = applicant_score(app.rank, pdata)
        return exp(-((app_toffer - toffer)/criteria.σd)^2/2 - ((app_score - score)/criteria.σs)^2/2)
    end
end

"""
    normdate(t::Date, pdata)

Express `t` as a fraction of the gap between the first offer date and last decision date as stored in `pdata`.
"""
function normdate(t::Date, pdata)
    clamp((t - pdata.firstofferdate) / (pdata.lastdecisiondate - pdata.firstofferdate), 0, 1)
end
normdate(t::Real, pdata) = t

applicant_score(rank::Int, pdata) = rank / pdata.napplicants

program_data(application, program_history) = program_history[program_key(application, program_history)]

program_key(application, ::Dict{<:NamedTuple}) = (year=season(application), program=application.program)

season(application) = year(application.offerdate) + (month(application.offerdate) > 7)

end
