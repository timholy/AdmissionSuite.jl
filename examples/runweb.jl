using AdmissionsSimulation
using Dates

function hide_decision!(applicants, program_history, tnow::Date)
    for (i, app) in pairs(applicants)
        pd = program_history[ProgramKey(app)]
        ntnow = normdate(tnow, pd)
        if app.normdecidedate > ntnow
            applicants[i] = NormalizedApplicant(app.applicantdata,
                                                app.program,
                                                app.season,
                                                app.normrank,
                                                app.normofferdate,
                                                missing,
                                                missing)
        end
    end
    return applicants
end

if !isdefined(@__MODULE__, :cur_applicants)
    include("prep_web.jl")
end

nmatric, prog_status, prog_projections, pq, new_offers = AdmissionsSimulation.recommend(past_applicants, cur_applicants, program_history, tnow)
AdmissionsSimulation.visualize(nmatric, prog_status, prog_projections, pq, new_offers, program_history, tnow)
