using LatexPrint

if isdefined(Main, :startdf)
    # Define rankstate="withrank" or "progonly" depending on whether you're running ranktest.jl
    # or setting σ from the _pg variants
    open("program_start_predictions_$rankstate.tex", "w") do io
        tabular(io, startdf)
    end

    for (dt, (_,df)) in sort(collect(pairs(seasonstatus)); by=first)
        open("program_$(dt)_predictions_$rankstate.tex", "w") do io
            tabular(io, df)
        end
    end
end

if isdefined(Main, :dfslots)
    open("program_weights_table.tex", "w") do io
        tabular(io, dfweights)
    end
    open("program_targets_table.tex", "w") do io
        tabular(io, dfslots)
    end
    open("nfaculty_table.tex", "w") do io
        tabular(io, dfscheme)
    end
    open("mergeresults_table.tex", "w") do io
        tabular(io, mergeresults)
    end
    open("napplicants_table.tex", "w") do io
        tabular(io, dfnapplicants)
    end
end

if isdefined(Main, :final_class)
    open("final_class_table_rolling.tex", "w") do io
        tabular(io, final_class)
    end
end

if isdefined(Main, :dftweaks)
    open("tweaked_slots.tex", "w") do io
        tabular(io, dftweaks)
    end
end
