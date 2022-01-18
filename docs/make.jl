using Admit
using AdmissionTargets
using AdmitConfiguration
using Documenter

DocMeta.setdocmeta!(Admit, :DocTestSetup, :(using Admit); recursive=true)

makedocs(;
    modules=[Admit],
    authors="Tim Holy <tim.holy@gmail.com> and contributors",
    repo="https://github.com/timholy/AdmissionSuite.jl/blob/{commit}{path}#{line}",
    sitename="AdmissionSuite.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://timholy.github.io/AdmissionSuite.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Configuration" => "configuration.md",
        "Web application" => "web.md",
        "How AdmissionSuite works" => [
            "Offers" => "simulation.md",
            "Targets" => "targets.md",
        ],
        "API" => "api.md"
    ],
)

deploydocs(;
    repo="github.com/timholy/AdmissionSuite.jl",
    devbranch="main",
    push_preview=true,
)
