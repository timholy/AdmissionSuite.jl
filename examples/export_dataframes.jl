using LatexPrint

if isdefined(Main, :startdf)
    open("program_start_predictions.tex", "w") do io
        tabular(io, startdf)
    end

    for (dt, (_,df)) in sort(collect(pairs(seasonstatus)); by=first)
        open("program_$(dt)_predictions.tex", "w") do io
            tabular(io, df)
        end
    end
end

if isdefined(Main, :comparedf)
    open("program_targets_table.tex", "w") do io
        tabular(io, comparedf)
    end
end
