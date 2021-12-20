function setprograms(filename::AbstractString; kwargs...)
    empty!(program_lookups)
    empty!(program_abbreviations)
    empty!(program_range)
    empty!(program_substitutions)
    rm(joinpath(@__DIR__, "LocalPreferences.toml"); force=true)
    tbl = CSV.File(filename)
    for row in tbl
        push!(program_abbreviations, row.Abbreviation)
        haskey(row, :ProgramName) && row.ProgramName !== missing && (program_lookups[row.ProgramName] = row.Abbreviation)
        seasonstart = haskey(row, :SeasonStart) ? coalesce(row.SeasonStart, 0) : 0
        seasonend = haskey(row, :SeasonEnd) ? coalesce(row.SeasonEnd, typemax(Int)) : typemax(Int)
        program_range[row.Abbreviation] = seasonstart:seasonend
        if haskey(row, :MergeTo) && row.MergeTo !== missing
            row.SplitFrom === missing || error("cannot set both MergeTo and SplitFrom in $(row.Abbreviation)")
            list = get!(Vector{String}, program_substitutions, row.Abbreviation)
            push!(list, row.MergeTo)
        elseif haskey(row, :SplitFrom) && row.SplitFrom !== missing
            list = get!(Vector{String}, program_substitutions, row.SplitFrom)
            push!(list, row.Abbreviation)
        end
    end
    # tomlfile = joinpath(suitedir, "LocalPreferences.toml")
    # set_preferences!(tomlfile, "AdmitConfiguration",
    set_preferences!(@__MODULE__,
                     "program_lookups" => program_lookups,
                     "program_abbreviations" => collect(program_abbreviations),
                     "program_range" => Dict(name => Dict("start"=>first(rng), "stop"=>last(rng)) for (name, rng) in program_range),
                     "program_substitutions" => program_substitutions;
                     kwargs...
                     )
end
