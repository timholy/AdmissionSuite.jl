using AdmissionsSimulation
using DataFrames

# First, try to replicate last years' results
yr = 2021
this_season = filter(pr->pr.first.season == yr, program_history)
program_applicants = Dict(pk.program => pd.napplicants for (pk, pd) in this_season)
# Last year we used unnormalized FII
fiis = faculty_involvement(faculty_engagement; normalize=false, iswarn=false)
prognames = sort(collect(keys(fiis)))
rawdblfiis = [round(fiis[prog]; digits=1) for prog in prognames]
# Corrections applied manually
fiis["BIDS"] = fiis["HSG"]
fiis["CB"] = 3*fiis["CB"]
oldfiis = [round(fiis[prog]; digits=1) for prog in prognames]
tgts = targets(program_applicants, fiis, sum(pr->pr.second.target_corrected, this_season), 0.0) #2.5)  # we gave slots to small programs

fiis = faculty_involvement(faculty_engagement; iswarn=false)
rawfiis = [round(fiis[prog]; digits=1) for prog in prognames]
# Corrections: CB & BIDS have essentially no thesis committees, so they can't compete with others; also, CB has a history of faculty
# who were contributing to other programs
fiis["CB"] = 30
fiis["BIDS"] = 20
fiis["MCB"] -= 15
corfiis = [round(fiis[prog]; digits=1) for prog in prognames]
tgtsn = targets(program_applicants, fiis, sum(pr->pr.second.target_corrected, this_season))

apps = [this_season[ProgramKey(prog, yr)].napplicants for prog in prognames]

compare = sort([pk.program => (pd.target_corrected, round(tgts[pk.program]; digits=1), round(tgtsn[pk.program]; digits=1)) for (pk,pd) in this_season])
comparedf = DataFrame("Program" => first.(compare), "DblCount FII"=>rawdblfiis, "Normed FII"=>rawfiis, "Corrected FII"=>corfiis, "Applicants"=>apps, "2021 target" => (x->x.second[1]).(compare), "2021 approx" => (x->x.second[2]).(compare), "2021 normed" => (x->x.second[3]).(compare))