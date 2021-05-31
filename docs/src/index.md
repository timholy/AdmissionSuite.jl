```@meta
CurrentModule = AdmissionsSimulation
```

# AdmissionsSimulation

[AdmissionsSimulation](https://github.com/timholy/AdmissionsSimulation.jl) is designed to simulate outcomes of
graduate admissions, with the intent of helping make decisions about both initial offers and wait-list offers.

This package focuses on those students to whom offers of admission have been extended, and uses past applicants as proxies for current applicants to make predictions about whether they'll accept the offer. Because two "similar" students might end up making different final decisions, the recommended practice is to identify many different potential proxies and use the distribution of their decisions to simulate future outcomes.

The inputs to this process are:
- records on previous applicants
- criteria for deciding the similarity between two students, resulting in a matching function computing a value between 0 (no match) and 1 (a perfect match).

## Applicant records

Records on previous applicants are in two forms: very general information is stored in `program_history`,
a dictionary recording just a few bits of information for each program. For example:

```julia
    program_history = Dict((year=2021, program=:NS) => (slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                           (year=2021, program=:CB) => (slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")),

```
suffices to record aggregate data for two programs, `:NS` and `:CB`, during the 2021 season (corresponding to a decision deadline of April 15, 2021). This records the target number of matriculants (`slots`), the total number of applications received, the date of the very first offers extended, and the date on which a decision was due.

Detailed applicant records only need to include applicants to whom an offer of admission was extended.
The requirements are described by [`NormalizedApplicant(applicant; program_history)`](@ref).

## match criteria

Applicants 1 and 2 are matched by the following function:

```math
\exp\left( - \frac{(r_1 - r_2)^2}{2 \sigma_r^2} - \frac{(t_1 - t_2)^2}{2 \sigma_t^2}\right)
```
where ``r`` refers to the normalized ranks and ``t`` to the normalized offer date.
The ``\sigma`` parameters measure the standard deviation, i.e., the tolerance for mismatch (larger ``\sigma`` are
more tolerant of mismatch).
Smaller ``\sigma_r`` increases the importance of choosing applicants of similar rank, and would indicate
that there may be a strong rank-dependent element to recruitment (e.g., "more competitive applicants are
harder to recruit").
Smaller ``\sigma_t`` increases the importance of the timing of the offer, and would indicate that
wait-list offers should be treated quite differently from initial offers.
The units of both ``\sigma`` parameters are those of the `NormalizedApplicant`s, i.e., with values ranging
between 0 and 1.
For example, setting ``\sigma_t = 0.2`` would, in essence, break the decision period (typically mid-January to April 15th) into roughly 5 periods, and match against applicants only extended offers during the same period.
Note that the applicant ranks will typically be quite heavily weighted to low values (e.g., a program that only
accepts the top 20% of applicants will only exhibit ranks between 0.0 and 0.2), and as a consequence ``\sigma_r`` must
be smaller than this span to have large effect.

This fundamental matching function is augmented by options to require a match between programs and the possibility to
exclude past applicants who had already rendered their decision by this point in the admissions season.
(The latter is intended to support modeling the currently-undecided applicants solely in terms of prior applicants
who were also undecided at this point.) See [`match_function`](@ref) for specific details.

## Running simulations

Once you've entered student records and defined a matching function, then for each outstanding offer you can compute the match likelihood of previous applicants using [`match_clikelihood`](@ref).
The final element in the returned list is a rough measure of the "number" of prior applicants deemed to be a good match
for the applicant you are modeling; if this value is small, your criteria for matching may be too stringent.
Conversely, if this value is approximately equal to the total number of prior applicants, you're essentially treating
all students as equivalent.

Once the likelihood is computed, [`select_applicant`](@ref) then allows you to randomly sample these by likelihood, and serves as the basis for running simulations about outcomes.

## API reference

```@autodocs
Modules = [AdmissionsSimulation]
```
