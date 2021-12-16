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

fetch_past_applicants() = past_applicants
fetch_applicants() = cur_applicants
fetch_program_data() = program_history

AdmissionsSimulation.visualize(fetch_past_applicants, fetch_applicants, fetch_program_data, tnow)
