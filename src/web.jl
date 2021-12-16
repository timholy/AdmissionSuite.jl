# Plotting & web-rendering functions

using Dash
using DashBootstrapComponents

function recommend(past_applicants, applicants, program_history, args...; σsel=0.2f0, σyield=1.0f0, σr=0.5f0, σt=Inf32)
    fmatch = match_function(past_applicants, program_history; σsel, σyield, σr, σt)
    return recommend(fmatch, past_applicants, applicants, args...; program_history)
end

function recommend(fmatch::Function, past_applicants, applicants, target, tnow::Date=today(), args...; program_history)
    progs = unique(app.program for app in applicants)
    _, prog_projection = wait_list_analysis(fmatch, past_applicants, applicants, tnow; program_history)
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
    prog_status = Dict(prog => (noffers=length(offers), outcomes=sum(Outcome, offers; init=Outcome()), nwaiting=length(program_candidates[prog])) for (prog, offers) in program_offers)
    # Extend offers, if desired
    nmatricpair, (pq, _) = add_offers!(fmatch, program_offers, program_candidates, past_applicants, tnow, args...; target, program_history)
    new_offers = Dict(prog => program_offers[prog][prog_status[prog][1]+1:end] for prog in progs)
    return nmatricpair, prog_status, prog_projection, pq, new_offers
end

function visualize(fetch_past_applicants::Function, fetch_applicants::Function, fetch_program_data::Function, tnow::Union{Date,Function}=today(), args...;
                   σsel=0.2f0, σyield=1.0f0, σr=0.5f0, σt=Inf32)
    get_tnow(tnow) = isa(tnow, Date) ? tnow : tnow()

    past_applicants = fetch_past_applicants()
    program_history = fetch_program_data()
    offerdat = offerdata(past_applicants, program_history)
    yielddat = yielddata(Tuple{Outcome,Outcome,Outcome}, past_applicants)
    progsim = cached_similarity(σsel, σyield; offerdata=offerdat, yielddata=yielddat)
    fmatch = match_function(; σr, σt, progsim)
    _season = season(get_tnow(tnow))

    applicants = Ref(fetch_applicants())
    progs = sort(unique(app.program for app in applicants[]))
    target = compute_target(program_history, _season)

    target_input = dcc_input(id="total-target", value=compute_target(program_history, season(get_tnow(tnow))), type="number")
    program_sel = dcc_dropdown(
        id = "program-selector",
        options = [(label=prog, value=prog) for prog in progs],
        value = first(progs),
        style = Dict("width" => "120px"),
    )
    refresh_btn = dbc_button("Refresh applicants", id="refresh-button", n_clicks=0, color="primary", class_name="me-1")

    tabs = html_div([
        dbc_tabs(
            [
                dbc_tab(label = "Summary",   tab_id = "tab-summary"),
                dbc_tab(label = "Program",   tab_id = "tab-program"),
                dbc_tab(label = "Internals", tab_id = "tab-internals"),
            ],
            id = "tabs",
            active_tab = "tab-summary",
        ),
        html_div(id = "content"),
        html_div(id = "hidden-div", style=Dict("display" => "none")),
    ])

    app = dash(external_stylesheets=[dbc_themes.BOOTSTRAP])

    app.layout = html_div() do
        [html_div([html_div([dbc_label("Total target: "),
                             target_input,
                            ]),
                   program_sel,
                   refresh_btn,
                  ], className = "d-grid gap-2 d-md-flex justify-content-md-end"),
         tabs,
        ]
    end

    # Tab-switcher callback
    callback!(app, Output("content", "children"), Input("tabs", "active_tab"), Input("total-target", "value"), Input("program-selector", "value"), Input("refresh-button", "n_clicks")) do active_tab, tgt, prog, _
        if active_tab == "tab-summary"
            target = tgt
            return render_tab_summary(fmatch, past_applicants, applicants[], get_tnow(tnow), program_history, target)
        elseif active_tab == "tab-program"
            return render_program_zoom(fmatch, past_applicants, filter(app->app.program==prog, applicants[]), get_tnow(tnow), program_history[ProgramKey(prog, _season)])
        elseif active_tab == "tab-internals"
            return render_internals(progsim, progs)
        else
            return html_p("This shouldn't ever be displayed...")
        end
    end

    # Refresh callback
    callback!(app, Output("hidden-div", "children"), Input("refresh-button", "n_clicks")) do n
        applicants[] = fetch_applicants()
        return nothing
    end

    run_server(app, "0.0.0.0", debug=true)
end

function render_tab_summary(fmatch, past_applicants, applicants, tnow::Date, program_history, target)
    (nmatric0, nmatric), prog_status, prog_projections, pq, new_offers = recommend(fmatch, past_applicants, applicants, target, tnow; program_history)
    _season = season(tnow)

    # The program-status table
    colnames = ["Program", "Target", "Projection", "# accepts", "# declines", "# pending", "# unoffered", "Priority"]
    prognames = sort(collect(keys(prog_projections)))
    status_tbl = dbc_table([
        html_thead(html_tr([html_th(col) for col in colnames])),
        html_tbody([
            html_tr([html_td(prog),
                    html_td(program_history[ProgramKey(prog, _season)].target_corrected),
                    html_td(string(prog_projections[prog].nmatriculants)),
                    html_td(prog_status[prog][2].naccepts),
                    html_td(prog_status[prog][2].ndeclines),
                    html_td(prog_status[prog][1] - total(prog_status[prog][2])),
                    html_td(prog_status[prog][3]),
                    html_td(get(pq, prog, 0.0)),
                ]) for prog in prognames
            ]),
        ]; hover=true)

    # The suggested-offers table
    rows = []
    for (prog, newoff) in new_offers
        isempty(newoff) && continue
        push!(rows, html_tr([html_td(prog), html_td(first(newoff).applicantdata.name)]))
        for off in Iterators.drop(newoff, 1)
            push!(rows, html_tr([html_td(""), html_td(off.applicantdata.name)]))
        end
    end
    suggested_tbl = html_table([
        html_thead(html_tr([html_th(col) for col in ("Program", "Candidate")])),
        html_tbody(rows),
    ])

    # The overall layout
    return dbc_card(
        dbc_cardbody([
            html_h1(string("Admissions report for ", tnow), style=Dict("textAlign" => "center")),
            html_div(string("Total target: ", target)),
            html_div(string("Total estimate: ", nmatric0)),
            html_br(),
            html_h3("Program status"),
            status_tbl,
            html_br(),
            html_h3("Suggested offers"),
            html_div(string("Bringing total estimate to ", nmatric)),
            suggested_tbl,
        ]),
        className = "mt-3",
    )
end

function render_program_zoom(fmatch, past_applicants, applicants, tnow::Date, pd::ProgramData)
    function calc_pmatric(applicant)  # TODO? copied from add_offers!, would be better not to copy but it's a closure...
        ntnow = normdate(tnow, pd)
        applicant.normdecidedate !== missing && applicant.normdecidedate <= ntnow && return Float32(applicant.accept)
        like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
        return matriculation_probability(like, past_applicants)
    end
    ntnow = normdate(tnow, pd)
    function pending_row(app)
        name = app.applicantdata.name
        if app.normofferdate !== missing && app.normofferdate <= ntnow
            name = html_b(name)
        end
        return [html_td(name), html_td(calc_pmatric(app))]
    end
    accepted, declined, undecided = eltype(applicants)[], eltype(applicants)[], eltype(applicants)[]
    for app in applicants
        if app.accept === true
            push!(accepted, app)
        elseif app.accept === false
            push!(declined, app)
        else
            push!(undecided, app)
        end
    end
    return dbc_card(
        dbc_cardbody([
            html_h2("Accepted:"),
            html_table(html_tbody([html_tr([html_td(app.applicantdata.name)]) for app in accepted])),
            html_br(),
            html_h2("Declined:"),
            html_table(html_tbody([html_tr([html_td(app.applicantdata.name)]) for app in declined])),
            html_br(),
            html_h2("Pending:"),
            html_table([
                html_thead(html_tr([html_th(col) for col in ("Candidate", "Probability")])),
                html_tbody([html_tr(pending_row(app)) for app in undecided]),
            ]),
        ])
    )
end

function render_internals(progsim, progs)
    psim = [[progsim(px, py) for px in progs] for py in progs]
    return dbc_card(
        dbc_cardbody([
            dcc_graph(
                id = "progsim",
                figure = (
                    data = [
                        (x = progs, y = progs, z = psim, type = "heatmap", transpose = "true"),
                     ],
                     layout = (title = "Program similarity", yaxis = (scaleanchor = "x",)),
                ),
            )
        ]),
        style = Dict("width" => 500),
    )
end
