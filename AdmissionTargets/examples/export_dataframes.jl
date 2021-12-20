using LatexPrint

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

if isdefined(Main, :dftweaks)
    open("tweaked_slots.tex", "w") do io
        tabular(io, dftweaks)
    end
    open("gradual_slots.tex", "w") do io
        tabular(io, dfgradual)
    end
end
