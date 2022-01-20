# Plotting & web-rendering functions

using Dash
using DashBootstrapComponents

get_tnow(tnow) = isa(tnow, Date) ? tnow : tnow()

function runweb(conn; deduplicate::Bool=false, tnow=today, kwargs...)
    local applicants, program_history
    refresh = Ref(true)
    function fetch_all()
        if refresh[]
            applicants, program_history = parse_database(conn; deduplicate)
            refresh[] = false
        end
    end
    function fetch_past_applicants()
        fetch_all()
        return filter(applicants) do app
            app.season < season(get_tnow(tnow)) && !ismissing(app.accept)
        end
    end
    function fetch_applicants()
        fetch_all()
        return filter(applicants) do app
            app.season == season(get_tnow(tnow))
        end
    end
    function fetch_program_data()
        fetch_all()
        return program_history
    end
    app = manage_offers(fetch_past_applicants, fetch_applicants, fetch_program_data, tnow; kwargs...)
    run_server(app, "0.0.0.0", debug=true)
end

"""
    app = manage_offers(fetch_past_applicants::Function, fetch_applicants::Function, fetch_program_data::Function, tnow::Union{Date,Function}=today;
                        σthresh::Real=2,
                        σsel=0.2f0, σyield=1.0f0, σr=0.5f0, σt=Inf32)

Create a report about the current state of admissions. The report has 3 tabs:

- "Summary" gives an overview across all programs, along with a list of candidates deemed ready to receive an offer given the target in the entry box at the top right.
- "Program" provides a detailed view of a single program selected in the dropdown at the top right, showing candidates who have accepted or rejected
  the offer of admission, along with a predicted matriculation probability for each undecided applicant.
- "Internals" provides information about the model details, currently just the "Program similarity" score which expresses the
  use of cross-program data in predicting matriculation probability.

The "Refresh applicants" button fetches fresh data about the current applicants, and should be used to update projections as decisions
get made.

The input arguments are:

- `fetch_past_applicants()` should return a list of `NormalizedApplicant`s from previous admissions years. These will be used to make predictions about
  the decisions of current applicants.
- `fetch_applicants()` should return a list of `NormalizedApplicant`s from the current season. This gets called every time you click "Refresh applicants".
- `fetch_program_data()` should return a `Dict{ProgramKey,ProgramData}` containing overall statistics about the program over the time covered by
  the combination of `fetch_past_applicants` and `fetch_applicants`.
- `tnow` can either be a `Date` or a function returning a `Date`. The default, the function `Dates.today`, will update the date every time the page renders.
  Pass a static date only if you don't want the date updating.
- `σthresh` determines how conservative the system will be in extending wait-list offers. On the "Summary" tab, the "Total estimate" will be expressed as
  `mean ± stddev`, and `mean + σthresh * stddev` will be held approximately at the total target. Larger values of `σthresh` make it less likely that you'll
  overshoot, and more likely that you'll undershoot. Values in the range of 0-3 seem like plausible choices (default: 2).
- `σsel` and `σyield` determine the cross-program similarity (see [`program_similarity`](@ref))
- `σr` and `σt` determine how much the prediction uses applicant rank and offer date, respectively (see [`match_function`](@ref)).

To render the report in a browser, use

```
Admit.run_server(app, "0.0.0.0", debug=true)
```
"""
function manage_offers(fetch_past_applicants::Function, fetch_applicants::Function, fetch_program_data::Function, tnow::Union{Date,Function}=today();
                       σthresh=2, σsel=0.2f0, σyield=1.0f0, σr=0.5f0, σt=Inf32, refresh=Ref(false))
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
                dbc_tab(label = "Initial",   tab_id = "tab-initial"),
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
            return render_tab_summary(fmatch, past_applicants, applicants[], get_tnow(tnow), program_history, target, σthresh)
        elseif active_tab == "tab-program"
            return render_program_zoom(fmatch, past_applicants, filter(app->app.program==prog, applicants[]), get_tnow(tnow), program_history[ProgramKey(prog, _season)], prog)
        elseif active_tab == "tab-initial"
            return render_tab_initial(fmatch, past_applicants, applicants[], Date(_season), program_history, target, σthresh)
        elseif active_tab == "tab-internals"
            return render_internals(fmatch, past_applicants, applicants[], get_tnow(tnow), program_history, progsim, progs)
        else
            return html_p("An unexpected tab error occurred, please report how to trigger this error")
        end
    end

    # Refresh callback
    callback!(app, Output("hidden-div", "children"), Input("refresh-button", "n_clicks")) do n
        refresh[] = true
        applicants[] = fetch_applicants()
        return nothing
    end

    return app
end

function render_tab_summary(fmatch::Function,
                            past_applicants::AbstractVector{NormalizedApplicant},
                            applicants::AbstractVector{NormalizedApplicant},
                            tnow::Date,
                            program_history,
                            target::Real,
                            σthresh::Real)
    (nmatric0, nmatric), prog_status, prog_projections, pq, new_offers = recommend(fmatch, past_applicants, applicants, target, tnow, σthresh; program_history)
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

function render_program_zoom(fmatch::Function,
                             past_applicants::AbstractVector{NormalizedApplicant},
                             applicants::AbstractVector{NormalizedApplicant},
                             tnow::Date,
                             pd::ProgramData,
                             prog::AbstractString)
    function calc_pmatric(applicant)  # TODO? copied from add_offers!, would be better not to copy but it's a closure...
        ndd = applicant.normdecidedate
        ndd !== missing && ndd <= ntnow && return Float32(applicant.accept::Bool)
        like = match_likelihood(fmatch, past_applicants, applicant, ntnow)
        return matriculation_probability(like, past_applicants)
    end
    function pending_row(app)
        name = app.applicantdata.name
        nod = app.normofferdate
        if nod !== missing && nod <= ntnow
            name = html_b(name)
        end
        return [html_td(name), html_td(round(calc_pmatric(app); digits=2))]
    end

    ntnow = normdate(tnow, pd)
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
    sort!(undecided; by=app->app.normrank)

    # Data for the response-date
    yes = Float64[]
    no = Float64[]
    seasonrange = (typemax(Int), typemin(Int))
    update_range((_min, _max), x) = (min(_min, x), max(_max, x))
    for app in past_applicants
        app.program == prog || continue
        ndd = app.normdecidedate
        isa(ndd, Real) || continue
        if app.accept === true
            push!(yes, ndd)
            seasonrange = update_range(seasonrange, app.season)
        elseif app.accept === false
            push!(no, ndd)
            seasonrange = update_range(seasonrange, app.season)
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
            html_div("Boldface indicates candidates with a pending offer, the rest are wait-listed"),
            dbc_table([
                html_thead(html_tr([html_th("Candidate"; style=Dict("width"=>"80%")), html_th("Probability"; style=Dict("width"=>"20%"))])),
                html_tbody([html_tr(pending_row(app)) for app in undecided]),
            ]; hover=true, style=Dict("width"=>"auto")),
            html_br(),
            dcc_graph(
                id = "timing",
                figure = (
                    data = [
                        (x = yes, type = "histogram", name = "accept"),
                        (x = no,  type = "histogram", name = "decline"),
                        #= FIXME: vertical line does not naturally span the y-domain =#
                        (xref = "x", yref = "y domain", x = [ntnow, ntnow], y = [0.0, 10.0], type = "line", line = (dash = "dash", width = 3), name = "today"),
                    ],
                    layout = (title = "Decision timing ($(seasonrange[1])-$(seasonrange[2]))", xaxis = (title = "Normalized date",)),
                )
            )
        ])
    )
end

function render_tab_initial(fmatch::Function,
                            past_applicants::AbstractVector{NormalizedApplicant},
                            applicants::AbstractVector{NormalizedApplicant},
                            startdate::Date,
                            program_history,
                            target::Real,
                            σthresh::Real)
    init_offers_by_prog, nmatrici = initial_offers!(fmatch, build_program_candidates(applicants), past_applicants, startdate,  σthresh; program_history)
    wl_by_prog, npool             = initial_offers!(fmatch, build_program_candidates(applicants), past_applicants, startdate, -σthresh; program_history)
    noffers = Dict(prog => length(list) for (prog, list) in init_offers_by_prog)
    nwl     = Dict(prog => length(list) for (prog, list) in wl_by_prog)
    _season = season(startdate)

    colnames = ["Program", "Target", "# potential offers", "# initial offers"]
    prognames = sort(collect(keys(init_offers_by_prog)))
    tbl = dbc_table([
                     html_thead(html_tr([html_th(col) for col in colnames])),
                     html_tbody(vcat([
                                      html_tr([html_td(prog),
                                              html_td(program_history[ProgramKey(prog, _season)].target_corrected),
                                              html_td(nwl[prog]),
                                              html_td(noffers[prog]),
                                          ]) for prog in prognames
                                     ],
                                     [html_tr([
                                         html_td("Total"),
                                         html_td(target),
                                         html_td(string(npool)),
                                         html_td(string(nmatrici))
                                         ])]
                                     ),
                     )
                    ]; hover=true, style=Dict("width"=>"auto"))

    # The overall layout
    return dbc_card(
        dbc_cardbody([
            html_h1(string("Season start (", startdate, ")"), style=Dict("textAlign" => "center")),
            tbl,
            html_p("# potential offers = suggested number of candidates you should have in the initial pool (offers + wait list)"),
            html_p("# initial offers = suggested number of candidates who receive an offer of admission at the beginning of the season"),
            html_br(),
            html_p("Based on buffer of $σthresh times the standard deviation"),
        ]),
        className = "mt-3",
    )
end

function render_internals(fmatch::Function,
                          past_applicants::AbstractVector{NormalizedApplicant},
                          applicants::AbstractVector{NormalizedApplicant},
                          tnow::Date,
                          program_history,
                          progsim::Function,
                          progs::AbstractVector{<:AbstractString})
    _season = season(tnow)
    psim = [[progsim(px, py) for px in progs] for py in progs]
    nmatches = Dict{String,Measurement{Float64}}()
    for prog in progs
        nsim = Float64[]
        ntnow = normdate(tnow, program_history[ProgramKey(program=prog, season=_season)])
        for app in applicants
            ndd = app.normdecidedate
            app.program == prog && (ismissing(ndd) || ndd > ntnow) || continue
            push!(nsim, sum(pastapp->fmatch(app, pastapp, ntnow), past_applicants))
        end
        nmatches[prog] = round(mean(nsim); digits=1) ± round(std(nsim); digits=1)
    end
    colnames = ["Program", "# of matches/applicant"]
    tbl = dbc_table([
        html_thead(html_tr([html_th(col) for col in colnames])),
        html_tbody([
            html_tr([html_td(prog),
                     html_td(string(nmatches[prog])),
                ]) for prog in sort(progs)
            ]),
        ]; hover=true, style=Dict("width"=>"auto"))


    return dbc_card(
        dbc_cardbody([
            dcc_graph(
                id = "progsim",
                figure = (
                    data = [
                        (x = progs, y = progs, z = psim, type = "heatmap", zmin = 0, zmax = 1, transpose = "true"),
                     ],
                     layout = (title = "Program similarity", yaxis = (scaleanchor = "x",)),
                ),
            ),
            html_br(),
            tbl,
        ]),
        style = Dict("width" => 500),
    )
end

function recommend(fmatch::Function,
                   past_applicants::AbstractVector{NormalizedApplicant},
                   applicants::AbstractVector{NormalizedApplicant},
                   target::Real,
                   tnow::Date,
                   σthresh::Real;
                   program_history)
    progs = unique(app.program for app in applicants)
    _, prog_projection = wait_list_analysis(fmatch, past_applicants, applicants, tnow; program_history)

    # Divide the applicants into those with offers and those not yet offered a slot
    program_offers = Dict(program => NormalizedApplicant[] for program in progs)
    program_candidates = Dict(program => NormalizedApplicant[] for program in progs)
    sapplicants = sort(applicants; by=app->(app.program, app.applicantdata.name))
    # Since the applicants are sorted by program, cache the program data `pd` between applicants to
    # the same program.
    cprog = first(sapplicants).program
    pd = program_history[ProgramKey(first(sapplicants))]
    for app in sapplicants
        if app.program != cprog   # we switched to a new program, look up its program data
            cprog = app.program
            pd = program_history[ProgramKey(app)]
        end
        ntnow = normdate(tnow, pd)
        nod = app.normofferdate
        if !ismissing(nod) && nod <= ntnow
            push!(program_offers[cprog], app)
        else
            push!(program_candidates[cprog], app)
        end
    end
    # Keep track of the number who already have offers
    prog_status = Dict(prog => (noffers=length(offers), outcomes=sum(Outcome, offers; init=Outcome()), nwaiting=length(program_candidates[prog])) for (prog, offers) in program_offers)
    # Extend offers, if desired
    nmatricpair, (pq, _) = add_offers!(fmatch, program_offers, program_candidates, past_applicants, tnow, σthresh; target, program_history)
    new_offers = Dict(prog => program_offers[prog][prog_status[prog][1]+1:end] for prog in progs)
    return nmatricpair, prog_status, prog_projection, pq, new_offers
end
