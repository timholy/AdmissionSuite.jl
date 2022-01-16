# Analyze primary/secondary/tertiary program affiliations

using CSV

if !isdefined(@__MODULE__, :facrecs)
    include("parsedata.jl")
end

const progidx = Dict(name => i for (name, i) in zip(pnames, 1:length(pnames)))
counts = zeros(Int, length(pnames))
pairings = zeros(Int, length(pnames), length(pnames))

for (_, facrec) in facrecs
    for (i1, prog1) in enumerate(facrec.programs)
        idx1 = progidx[prog1]
        counts[idx1] += 1
        # pairings[idx1,idx1] += 1
        for i2 = i1+1:length(facrec.programs)
            prog2 = facrec.programs[i2]
            idx2 = progidx[prog2]
            pairings[idx1, idx2] += 1
        end
    end
end

normpairings = pairings ./ sqrt.(counts .* counts')
