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

include("parsedata.jl")
current_applicants = filter(applicants) do app
    app.season == 2021
end;
past_applicants = filter(applicants) do app
    app.season < 2021
end;

tnow = Date("2021-02-28")
cur_applicants = hide_decision!(copy(current_applicants), program_history, tnow)
nmatric, prog_status, prog_projections, pq, new_offers = AdmissionsSimulation.recommend(past_applicants, cur_applicants, program_history, tnow)
AdmissionsSimulation.visualize(nmatric, prog_status, prog_projections, pq, new_offers, program_history, tnow)
