# Plotting & web-rendering functions

using Dash
using DashBootstrapComponents

function recommend(past_applicants, applicants, program_history, args...; σsel=0.2f0, σyield=1.0f0, σr=0.5f0, σt=Inf32)
    fmatch = match_function(past_applicants, program_history; σsel, σyield, σr, σt)
    return recommend(fmatch, past_applicants, applicants, args...; program_history)
end

function recommend(fmatch::Function, past_applicants, applicants, tnow::Date=today(), args...; program_history)
    progs = unique(app.program for app in applicants)
    nmatric, prog_projection = wait_list_analysis(fmatch, past_applicants, applicants, tnow; program_history)
    # Divide the applicants into those with offers and those not yet offered a slot
    program_offers = Dict(program => NormalizedApplicant[] for program in progs)
    program_candidates = Dict(program => NormalizedApplicant[] for program in progs)
    sapplicants = sort(applicants; by=app->app.program)
    # cprog = first(sapplicants).program
    # pd = program_history[ProgramKey(first(sapplicants))]
    for app in sapplicants
        # if app.program != cprog
            cprog = app.program
            pd = program_history[ProgramKey(app)]
        # end
        ntnow = normdate(tnow, pd)
        if app.normofferdate <= ntnow
            push!(program_offers[cprog], app)
        else
            push!(program_candidates[cprog], app)
        end
    end
    # for prog in progs
    #     println(prog, ": ", length(program_offers[prog]), " offers and ", length(program_candidates[prog]), " remaining")
    # end
    # Keep track of the number who already have offers
    prog_status = Dict(prog => (length(offers), sum(Outcome, offers; init=Outcome()), length(program_candidates[prog])) for (prog, offers) in program_offers)
    # Extend offers, if desired
    _, pq = add_offers!(fmatch, program_offers, program_candidates, past_applicants, tnow, args...; program_history)
    new_offers = Dict(prog => program_offers[prog][prog_status[prog][1]+1:end] for prog in progs)
    return nmatric, prog_status, prog_projection, pq, new_offers
end

function visualize(nmatric, prog_status, prog_projection, pq, new_offers, program_history, tnow::Date=today())
    season = year(tnow)
    target = compute_target(program_history, season)
    colnames = ["Program", "Target", "Projection", "# accepts", "# declines", "# remaining", "# unoffered", "Priority"]
    prognames = sort(collect(keys(prog_projection)))
    tbl = dbc_table([
        html_thead(html_tr([html_th(col) for col in colnames])),
        html_tbody([
            html_tr([html_td(prog),
                     html_td(program_history[ProgramKey(prog, season)].target_corrected),
                     html_td(string(prog_projection[prog].nmatriculants)),
                     html_td(prog_status[prog][2].naccepts),
                     html_td(prog_status[prog][2].ndeclines),
                     html_td(prog_status[prog][1] - total(prog_status[prog][2])),
                     html_td(prog_status[prog][3]),
                     html_td(get(pq, prog, 0.0)),
                ]) for prog in prognames
            ]),
        ]; hover=true)
    rows = []
    for (prog, newoff) in new_offers
        isempty(newoff) && continue
        push!(rows, html_tr([html_td(prog), html_td(first(newoff).applicantdata.name)]))
        for off in Iterators.drop(newoff, 1)
            push!(rows, html_tr([html_td(""), html_td(off.applicantdata.name)]))
        end
    end
    suggested = html_table([
        html_thead(html_tr([html_th(col) for col in ("Program", "Candidate")])),
        html_tbody(rows),
    ])

    app = dash(external_stylesheets=[dbc_themes.BOOTSTRAP])
    app.layout = html_div() do
        [
            html_h1(string("Admissions report for ", tnow), style=Dict("textAlign" => "center")),
            html_div([
                "Total target: ",
                dcc_input(id="total-target", value=string(target), type="number"),
            ]),
            html_div(string("Total estimate: ", nmatric)),
            html_br(),
            html_h3("Program status"),
            tbl,
            html_br(),
            html_h3("Suggested offers"),
            suggested,
        # dcc_graph(
        #     id = "example-graph-1",
        #     figure = (
        #         data = [
        #             (x = ["giraffes", "orangutans", "monkeys"], y = [20, 14, 23], type = "bar", name = "SF"),
        #             (x = ["giraffes", "orangutans", "monkeys"], y = [12, 18, 29], type = "bar", name = "Montreal"),
        #         ],
        #         layout = (title = "Dash Data Visualization", barmode="group")
        #     )
        # )
        ]
    end

    run_server(app, "0.0.0.0", debug=true)
end
