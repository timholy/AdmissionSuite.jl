```@meta
CurrentModule = AdmissionsSimulation
```

# AdmissionsSimulation

[AdmissionsSimulation](https://github.com/timholy/AdmissionsSimulation.jl) is designed help make choices in graduate admissions,
and contains utilities for allocating offers of admission and forecasting outcomes.
It is built around Washington University's [Division of Biology and Biomedical Sciences](https://dbbs.wustl.edu/Pages/index.aspx) (DBBS),
the [first cross-departmental graduate training program in the United States](https://faseb.onlinelibrary.wiley.com/doi/10.1096/fba.2020-00122) consisting of many different programs of study with coordinated admissions and funding.

This package has two main components:
- tools to calculate the target number of matriculants in each program ("what do we want to achieve?")
- tools to strategize extension of initial offers and wait-list offers ("how should we achieve it?")

Each main thread is described on a separate page.

This package also provides a browser-based application that can be used by admissions professionals to manage the
admissions season. This tool is described next.
