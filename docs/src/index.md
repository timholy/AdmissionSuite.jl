```@meta
CurrentModule = AdmissionsSimulation
```

# AdmissionsSimulation

[AdmissionsSimulation](https://github.com/timholy/AdmissionsSimulation.jl) is designed to simulate outcomes of
graduate admissions, with the intent of helping make decisions about both initial offers and wait-list offers.

This package focuses on those students to whom offers of admission have been extended, and uses past applicants as proxies for current applicants to make predictions about whether they'll accept the offer. Because two "similar" students might end up making different final decisions, the recommended practice is to identify many different potential proxies and use the distribution of their decisions to simulate future outcomes.  This is similar to a [k-nearest neighbors](https://en.wikipedia.org/wiki/K-nearest_neighbors_algorithm) algorithm, but with continuous weights applied to each potential neighbor and no limit on the number of neighbors used.

The inputs to this process are:
- records on previous applicants
- criteria for deciding the similarity between two students, resulting in a matching function computing a value between 0 (no match) and 1 (a perfect match).

The core concept may be easily explained by a simplified example.
Imagine that the admissions committee for "program A" has ranked their applicants for the season.
Let's focus on one "test" applicant, say their 2nd most highly-ranked applicant.
Let's imagine that the history of past admissions seasons looks like the first four columns below:

| Applicant | Program | Applicant rank | Accepted? | *Similarity to test applicant* |
|:--------- |:------- | ----:| ---------:| ---------------------------:|
| PastApplicant1 | A | 1 | no | 0.6 |
| PastApplicant2 | A | 2 | yes | 1.0 |
| PastApplicant3 | A | 3 | no | 0.6 |
| PastApplicant4 | A | 4 | yes | 0.4 |
| PastApplicant5 | B | 1 | yes | 0.1 |
| PastApplicant6 | B | 2 | no | 0.15 |

The final column is specific to this particular "test" applicant--the one being made an offer in the current season whose response to the offer of admission is currently unknown--and must be recomputed for each current applicant we want to examine.
The idea is that we look at all previous applicants who were also offered admission and assess similarity.
In this table, 4 of the applicants are also from "program A."
These are viewed as being especially similar to the test applicant, particularly the applicant who was also the 2nd most highly-ranked applicant in zir year (with a similarity score of "1.0").
However, in this case our matching function also allows us to use "intelligence" from other programs,
and so two applicants to "program B" have a small but nonzero similarity to the test applicant.

Now, to make predictions about how our test student will respond to our offer, we form a similarity-weighted sum of the previous yes/no decisions.
In this case, the probability of "yes" is (1.0 + 0.4 + 0.1)/(0.6 + 1.0 + 0.6 + 0.4 + 0.1 + 0.15) ≈ 0.53.
This gives us a quantitative assessment of the likelihood that our test applicant will accept our offer.
While each individual applicant must ultimately answer either yes or no,
the fundamental thesis of this package is that having a per applicant matriculation probability can allow better control over class sizes
through management of offer-extensions and wait-lists.

The actual model incorporates more factors than shown in this simplified example.
For example, we track the date on which each past applicant informed us of zir decision.
This allows us to account for the ways in which both applicant and program competitiveness may interact to lead some applicants to respond immediately to our offer of admission and others to wait until the last day of the season (typically April 15th), with the reasons for delay also being coupled to the likelihood of accepting the offer of admission (e.g., more "yes" decisions arrive early and more "no" decisions arrive late).
Accounting for these additional factors in our similarity computation improves accuracy in the projections for managing the wait list.

The remainder of this documentation describes the actual implementation.

## Applicant records

Records on previous applicants are in two forms: very general information is stored in `program_history`,
a dictionary recording just a few bits of information for each program. For example:

```julia
    program_history = Dict(ProgramKey(season=2021, program="NS") => ProgramData(slots=15, napplicants=302, firstofferdate=Date("2021-01-13"), lastdecisiondate=Date("2021-04-15")),
                           ProgramKey(season=2021, program="CB") => ProgramData(slots=5,  napplicants=160, firstofferdate=Date("2021-01-6"),  lastdecisiondate=Date("2021-04-15")))

```
suffices to record aggregate data for two programs, `"NS"` and `"CB"`, during the 2021 season (corresponding to a decision deadline of April 15, 2021). This records the target number of matriculants (`slots`), the total number of applications received, the date of the very first offers extended, and the date on which a decision was due.

Valid choices for program names are listed in `AdmissionsSimulation.program_lookups`; internally the code always uses
the abbreviation, but it is possible to supply it in long form too.

Detailed applicant records only need to include applicants to whom an offer of admission was extended.
The requirements are described by [`NormalizedApplicant(applicant; program_history)`](@ref).

You can load both the program history and data on applicants using [`read_program_history`](@ref) and [`read_applicant_data`](@ref).

## Match criteria

Applicants 1 and 2 are matched by the following function:

```math
\phi(p_1, p_2) \psi(r_1-r_2, t_1-t_2)
```
``\phi(p_1, p_2)`` is a measure of similarity between the two applicants' programs, ``p_1`` and ``p_2``,
based on program selectivity and yield.
The ``\psi`` term is applicant-specific, analyzing rank ``r`` and date ``t`` on which the offer of admission was made.

In the current implementation, programs are compared by selectivity ``s`` and yield ``y``. Selectivity is simply the fraction of applicants who receive offers of admission; yield is more complicated, because the proper handling of the wait list requires not just an estimate of how many applicants accept our offer, but also the typical timing with which they accept.  A program that ranks first in the world (or one whose admissions committee targets a lot of high-certainty applicants to reduce their risk of receiving rejections) might imagine receiving a lot of "yes" replies as soon as offers are extended, whereas a program with a lot of competition might have a larger number of delayed responses.  Consequently, by default the admissions season is broken into thirds, and the fraction of accepts/declines in each third is the basis for comparing yield in two programs. The formula for doing this is

```math
\phi(p_1, p_2) = \exp\left(-\frac{(s_1 - s_2)^2}{2\sigma_\text{sel}^2} - \frac{({\bf y}_1 - {\bf y}_2)^2}{2\sigma_\text{yield}^2}\right).
```

Here, ``{\bf y}`` is a vector encoding the fraction of accepts/declines in each period of the season, and a Euclidean distance is computed.

The ``\sigma`` parameters measure the standard deviation, i.e., the tolerance for mismatch (larger ``\sigma`` are
more tolerant of mismatch).
In the extreme of ``\sigma \ll 1``, each program matches only itself; in the extreme ``\sigma \gg 1``, each program matches every other program perfectly.  In between, programs will draw more "intelligence" from other programs with similar selectivity and yield dynamics as their own.
In practice, model-tuning (see below) seems to favor programs primarily relying on their own history.

The remaining terms are applicant-, rather than program-, specific:

```math
\psi(r_1-r_2, t_1-t_2) = \exp\left( - \frac{(r_1 - r_2)^2}{2 \sigma_r^2} - \frac{(t_1 - t_2)^2}{2 \sigma_t^2}\right)
```

``r`` refers to the normalized ranks and ``t`` to the normalized offer date.
Smaller ``\sigma_r`` increases the importance of choosing applicants of similar rank, and would indicate
that there may be a strong rank-dependent element to recruitment (e.g., "more competitive applicants are
harder to recruit").
Smaller ``\sigma_t`` increases the importance of the timing of the offer, and would indicate that
wait-list offers should be treated quite differently from initial offers.
The units of both ``\sigma`` parameters are those of the `NormalizedApplicant`s, i.e., with values ranging
between 0 and 1.
For example, setting ``\sigma_t = 0.2`` would, in essence, break the decision period (e.g., mid-January to April 15th) into roughly 5 periods, and match primarily against applicants who were extended offers during the same period;
conversely, setting ``\sigma_t = 5`` would mean that the timing of the offer is essentially irrelevant to predicting the decision.
Note that the applicant ranks will typically be quite heavily weighted to low values (e.g., a program that only
accepts the top 20% of applicants will only exhibit ranks between 0.0 and 0.2), and as a consequence ``\sigma_r`` must
be smaller than this span to have large effect.

One crucial point is that *the matching function returns zero when comparing against past applicants who had already returned
their decision by this point in the admissions season*. This models the currently-undecided applicants solely in terms of prior applicants who were also undecided at this point.
See [`match_function`](@ref) for specific details.

How does one tune these parameters? The core idea is to train them based on past admissions seasons: if you have
records extending back several years, you make matriculation predictions for year ``y`` based on data from all years up to
and including year ``y-1``, and then compute a correlation with the actual outcome.
See [`match_correlation`](@ref) for details.

## Analysis and simulations

Once you've entered student records and defined a matching function, then for each outstanding offer you can compute the match likelihood of previous applicants using [`match_likelihood`](@ref).
The sum of the returned list is a rough measure of the "number" of prior applicants deemed to be a good match
for the applicant you are modeling; if this value is small, your criteria for matching may be too stringent.
Conversely, if this value is approximately equal to the total number of prior applicants, you're essentially treating
all students as equivalent (and matching all of them).

Once the likelihood is computed, [`matriculation_probability`](@ref) estimates the probability that the given applicant
will accept an offer. [`select_applicant`](@ref) allows you to randomly sample these by likelihood, and may serve as the basis for running simulations about outcomes, although [`run_simulation`](@ref) (which just uses matriculation probability) may be a more useful approach.

## API reference

```@autodocs
Modules = [AdmissionsSimulation]
```
