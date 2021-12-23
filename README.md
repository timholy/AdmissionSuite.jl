# AdmissionSuite

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://timholy.github.io/AdmissionSuite.jl/dev)
[![Build Status](https://github.com/timholy/AdmissionSuite.jl/workflows/CI/badge.svg)](https://github.com/timholy/AdmissionSuite.jl/actions)
[![Coverage](https://codecov.io/gh/timholy/AdmissionSuite.jl/branch/main/graph/badge.svg?token=AdpeX8uLqa)](https://codecov.io/gh/timholy/AdmissionSuite.jl)

This suite of packages is designed for management and analysis of an admissions process in which one or more "programs" have a applicants and a target number of "slots" (matriculants) to fill. The primary features are:

- management of offers and the waitlist (including realtime interaction with a SQL database of applicants)
- machine-learning tools to forecast the probability of acceptance of each applicant
- allocation of slots across programs

This suite was written for graduate admissions at Washington University in St. Louis, Division of Biology and Biological Sciences (DBBS).
DBBS is an "umbrella" coordinating 13 different Ph.D. programs in the biomedical sciences. However, the suite can be configured for the specifics of your local institution.

See the documentation badge above for details about how to use the suite.
