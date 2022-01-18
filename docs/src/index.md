```@meta
CurrentModule = Admit
```

# AdmissionSuite

[AdmissionSuite](https://github.com/timholy/AdmissionSuite.jl) is designed to help allocate offers of admission, forecast outcomes, and allocate resources across programs.
It was designed around Washington University's [Division of Biology and Biomedical Sciences](https://dbbs.wustl.edu/Pages/index.aspx) (DBBS),
the [first cross-departmental graduate training program in the United States](https://faseb.onlinelibrary.wiley.com/doi/10.1096/fba.2020-00122) consisting of many different programs of study with coordinated admissions and funding.

The suite is organized into three sub-packages:

- `Admit` focuses on managing offers of admission and predicting the probability that candidates will accept them. It includes a browser-based application that can be used by admissions professionals to manage the admissions season.
- `AdmissionTargets` focuses on allocating "slots" among different programs, given a total target number of incoming students.
- `AdmitConfiguration` is used to configure the suite for your local institution
