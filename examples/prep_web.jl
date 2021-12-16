include("parsedata.jl")
current_applicants = filter(applicants) do app
    app.season == 2021
end;
past_applicants = filter(applicants) do app
    app.season < 2021
end;

tnow = Date("2021-02-28")
cur_applicants = hide_decision!(copy(current_applicants), program_history, tnow)
