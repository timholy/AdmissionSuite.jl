# AdmissionSuite

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://timholy.github.io/AdmissionSuite.jl/dev)
[![Build Status](https://github.com/timholy/AdmissionSuite.jl/workflows/CI/badge.svg)](https://github.com/timholy/AdmissionSuite.jl/actions)
[![Coverage](https://codecov.io/gh/timholy/AdmissionSuite.jl/branch/main/graph/badge.svg?token=AdpeX8uLqa)](https://codecov.io/gh/timholy/AdmissionSuite.jl)

This suite of packages is designed for management and analysis of admissions. It targets a multi-program admissions process, in which a pool of applicants will be evaluated by one or more committees for admittance to one or more programs. Each program is assumed to have a number of "slots" to fill. The primary features are:

- "fairly" allocate admission slots across programs, based on numbers of applicants and training capacity;
- manage offers and the waitlist (including realtime interaction with a SQL database of applicants);
- machine-learning tools to forecast the probability that each applicant will accept the offer of admission, thus predicting class size

This suite was written for graduate admissions at Washington University in St. Louis, Division of Biology and Biological Sciences (DBBS).
DBBS is an "umbrella" coordinating 12 different Ph.D. programs in the biomedical sciences. However, the suite can be configured for the specifics of your local institution.

See the documentation badge above for details about how to use the suite.
