using AdmissionsSimulation
using Documenter

DocMeta.setdocmeta!(AdmissionsSimulation, :DocTestSetup, :(using AdmissionsSimulation); recursive=true)

makedocs(;
    modules=[AdmissionsSimulation],
    authors="Tim Holy <tim.holy@gmail.com> and contributors",
    repo="https://github.com/timholy/AdmissionsSimulation.jl/blob/{commit}{path}#{line}",
    sitename="AdmissionsSimulation.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://timholy.github.io/AdmissionsSimulation.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/timholy/AdmissionsSimulation.jl",
)
