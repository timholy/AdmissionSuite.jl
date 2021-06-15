var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = AdmissionsSimulation","category":"page"},{"location":"#AdmissionsSimulation","page":"Home","title":"AdmissionsSimulation","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"AdmissionsSimulation is designed to simulate outcomes of graduate admissions, with the intent of helping make decisions about both initial offers and wait-list offers.","category":"page"},{"location":"","page":"Home","title":"Home","text":"This package focuses on those students to whom offers of admission have been extended, and uses past applicants as proxies for current applicants to make predictions about whether they'll accept the offer. Because two \"similar\" students might end up making different final decisions, the recommended practice is to identify many different potential proxies and use the distribution of their decisions to simulate future outcomes.  This is similar to a k-nearest neighbors algorithm, but with continuous weights applied to each potential neighbor and no limit on the number of neighbors used.","category":"page"},{"location":"","page":"Home","title":"Home","text":"The inputs to this process are:","category":"page"},{"location":"","page":"Home","title":"Home","text":"records on previous applicants\ncriteria for deciding the similarity between two students, resulting in a matching function computing a value between 0 (no match) and 1 (a perfect match).","category":"page"},{"location":"","page":"Home","title":"Home","text":"The core concept may be easily explained by a simplified example. Imagine that the admissions committee for \"program A\" has ranked their applicants for the season. Let's focus on one \"test\" applicant, say their 2nd most highly-ranked applicant. Let's imagine that the history of past admissions seasons looks like the first four columns below:","category":"page"},{"location":"","page":"Home","title":"Home","text":"Applicant Program Applicant rank Accepted? Similarity to test applicant\nPastApplicant1 A 1 no 0.6\nPastApplicant2 A 2 yes 1.0\nPastApplicant3 A 3 no 0.6\nPastApplicant4 A 4 yes 0.4\nPastApplicant5 B 1 yes 0.1\nPastApplicant6 B 2 no 0.15","category":"page"},{"location":"","page":"Home","title":"Home","text":"The final column is specific to this particular \"test\" applicant–the one being made an offer in the current season whose response to the offer of admission is currently unknown–and must be recomputed for each current applicant we want to examine. The idea is that we look at all previous applicants who were also offered admission and assess similarity. In this table, 4 of the applicants are also from \"program A.\" These are viewed as being especially similar to the test applicant, particularly the applicant who was also the 2nd most highly-ranked applicant in zir year (with a similarity score of \"1.0\"). However, in this case our matching function also allows us to use \"intelligence\" from other programs, and so two applicants to \"program B\" have a small but nonzero similarity to the test applicant.","category":"page"},{"location":"","page":"Home","title":"Home","text":"Now, to make predictions about how our test student will respond to our offer, we form a similarity-weighted sum of the previous yes/no decisions. In this case, the probability of \"yes\" is (1.0 + 0.4 + 0.1)/(0.6 + 1.0 + 0.6 + 0.4 + 0.1 + 0.15) ≈ 0.53. This gives us a quantitative assessment of the likelihood that our test applicant will accept our offer. While each individual applicant must ultimately answer either yes or no, the fundamental thesis of this package is that having a per applicant matriculation probability can allow better control over class sizes through management of offer-extensions and wait-lists.","category":"page"},{"location":"","page":"Home","title":"Home","text":"The actual model incorporates more factors than shown in this simplified example. For example, we track the date on which each past applicant informed us of zir decision. This allows us to account for the ways in which both applicant and program competitiveness may interact to lead some applicants to respond immediately to our offer of admission and others to wait until the last day of the season (typically April 15th), with the reasons for delay also being coupled to the likelihood of accepting the offer of admission (e.g., more \"yes\" decisions arrive early and more \"no\" decisions arrive late). Accounting for these additional factors in our similarity computation improves accuracy in the projections for managing the wait list.","category":"page"},{"location":"","page":"Home","title":"Home","text":"The remainder of this documentation describes the actual implementation.","category":"page"},{"location":"#Applicant-records","page":"Home","title":"Applicant records","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Records on previous applicants are in two forms: very general information is stored in program_history, a dictionary recording just a few bits of information for each program. For example:","category":"page"},{"location":"","page":"Home","title":"Home","text":"    program_history = Dict(ProgramKey(season=2021, program=\"NS\") => ProgramData(slots=15, napplicants=302, firstofferdate=Date(\"2021-01-13\"), lastdecisiondate=Date(\"2021-04-15\")),\n                           ProgramKey(season=2021, program=\"CB\") => ProgramData(slots=5,  napplicants=160, firstofferdate=Date(\"2021-01-6\"),  lastdecisiondate=Date(\"2021-04-15\")))\n","category":"page"},{"location":"","page":"Home","title":"Home","text":"suffices to record aggregate data for two programs, \"NS\" and \"CB\", during the 2021 season (corresponding to a decision deadline of April 15, 2021). This records the target number of matriculants (slots), the total number of applications received, the date of the very first offers extended, and the date on which a decision was due.","category":"page"},{"location":"","page":"Home","title":"Home","text":"Valid choices for program names are listed in AdmissionsSimulation.program_lookups; internally the code always uses the abbreviation, but it is possible to supply it in long form too.","category":"page"},{"location":"","page":"Home","title":"Home","text":"Detailed applicant records only need to include applicants to whom an offer of admission was extended. The requirements are described by NormalizedApplicant(applicant; program_history).","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can load both the program history and data on applicants using read_program_history and read_applicant_data.","category":"page"},{"location":"#Match-criteria","page":"Home","title":"Match criteria","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Applicants 1 and 2 are matched by the following function:","category":"page"},{"location":"","page":"Home","title":"Home","text":"phi(p_1 p_2) psi(r_1-r_2 t_1-t_2)","category":"page"},{"location":"","page":"Home","title":"Home","text":"phi(p_1 p_2) is a measure of similarity between the two applicants' programs, p_1 and p_2, based on program selectivity and yield. The psi term is applicant-specific, analyzing rank r and date t on which the offer of admission was made.","category":"page"},{"location":"","page":"Home","title":"Home","text":"In the current implementation, programs are compared by selectivity s and yield y. Selectivity is simply the fraction of applicants who receive offers of admission; yield is more complicated, because the proper handling of the wait list requires not just an estimate of how many applicants accept our offer, but also the typical timing with which they accept.  A program that ranks first in the world (or one whose admissions committee targets a lot of high-certainty applicants to reduce their risk of receiving rejections) might imagine receiving a lot of \"yes\" replies as soon as offers are extended, whereas a program with a lot of competition might have a larger number of delayed responses.  Consequently, by default the admissions season is broken into thirds, and the fraction of accepts/declines in each third is the basis for comparing yield in two programs. The formula for doing this is","category":"page"},{"location":"","page":"Home","title":"Home","text":"phi(p_1 p_2) = expleft(-frac(s_1 - s_2)^22sigma_textsel^2 - frac(bf y_1 - bf y_2)^22sigma_textyield^2right)","category":"page"},{"location":"","page":"Home","title":"Home","text":"Here, bf y is a vector encoding the fraction of accepts/declines in each period of the season, and a Euclidean distance is computed.","category":"page"},{"location":"","page":"Home","title":"Home","text":"The sigma parameters measure the standard deviation, i.e., the tolerance for mismatch (larger sigma are more tolerant of mismatch). In the extreme of sigma ll 1, each program matches only itself; in the extreme sigma gg 1, each program matches every other program perfectly.  In between, programs will draw more \"intelligence\" from other programs with similar selectivity and yield dynamics as their own. In practice, model-tuning (see below) seems to favor programs primarily relying on their own history.","category":"page"},{"location":"","page":"Home","title":"Home","text":"The remaining terms are applicant-, rather than program-, specific:","category":"page"},{"location":"","page":"Home","title":"Home","text":"psi(r_1-r_2 t_1-t_2) = expleft( - frac(r_1 - r_2)^22 sigma_r^2 - frac(t_1 - t_2)^22 sigma_t^2right)","category":"page"},{"location":"","page":"Home","title":"Home","text":"r refers to the normalized ranks and t to the normalized offer date. Smaller sigma_r increases the importance of choosing applicants of similar rank, and would indicate that there may be a strong rank-dependent element to recruitment (e.g., \"more competitive applicants are harder to recruit\"). Smaller sigma_t increases the importance of the timing of the offer, and would indicate that wait-list offers should be treated quite differently from initial offers. The units of both sigma parameters are those of the NormalizedApplicants, i.e., with values ranging between 0 and 1. For example, setting sigma_t = 02 would, in essence, break the decision period (e.g., mid-January to April 15th) into roughly 5 periods, and match primarily against applicants who were extended offers during the same period; conversely, setting sigma_t = 5 would mean that the timing of the offer is essentially irrelevant to predicting the decision. Note that the applicant ranks will typically be quite heavily weighted to low values (e.g., a program that only accepts the top 20% of applicants will only exhibit ranks between 0.0 and 0.2), and as a consequence sigma_r must be smaller than this span to have large effect.","category":"page"},{"location":"","page":"Home","title":"Home","text":"One crucial point is that the matching function returns zero when comparing against past applicants who had already returned their decision by this point in the admissions season. This models the currently-undecided applicants solely in terms of prior applicants who were also undecided at this point. See match_function for specific details.","category":"page"},{"location":"","page":"Home","title":"Home","text":"How does one tune these parameters? The core idea is to train them based on past admissions seasons: if you have records extending back several years, you make matriculation predictions for year y based on data from all years up to and including year y-1, and then compute a \"net log likelihood\" based on the actual outcome. See net_loglike for details.","category":"page"},{"location":"#Analysis-and-simulations","page":"Home","title":"Analysis and simulations","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Once you've entered student records and defined a matching function, then for each outstanding offer you can compute the match likelihood of previous applicants using match_likelihood. The sum of the returned list is a rough measure of the \"number\" of prior applicants deemed to be a good match for the applicant you are modeling; if this value is small, your criteria for matching may be too stringent. Conversely, if this value is approximately equal to the total number of prior applicants, you're essentially treating all students as equivalent (and matching all of them).","category":"page"},{"location":"","page":"Home","title":"Home","text":"Once the likelihood is computed, matriculation_probability estimates the probability that the given applicant will accept an offer. select_applicant allows you to randomly sample these by likelihood, and may serve as the basis for running simulations about outcomes, although run_simulation (which just uses matriculation probability) may be a more useful approach.","category":"page"},{"location":"#API-reference","page":"Home","title":"API reference","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [AdmissionsSimulation]","category":"page"},{"location":"#AdmissionsSimulation.NormalizedApplicant","page":"Home","title":"AdmissionsSimulation.NormalizedApplicant","text":"NormalizedApplicant holds normalized data about an applicant who received, or may receive, an offer of admission.\n\nprogram::String\nThe abbreviation of the program the applicant was admitted to. AdmissionsSimulation.program_lookups contains the list of valid choices, together with their full names.\n\nseason::Int16\nThe year in which the applicant's decision was due. E.g., if the last date was April 15th, 2021, this would be 2021.\n\nnormrank::Union{Missing, Float32}\nNormalized rank of the applicant: the top applicant has a rank near 0 (e.g., 1/302), and the bottom applicant has rank 1. The rank is computed among all applicants, not just those who received an offer of admission.\n\nnormofferdate::Float32\nNormalized date at which the applicant received the offer of admission. 0 = date of first offer of season, 1 = decision date (typically April 15th). Candidates who were admitted in the first round would have a value of 0 (or near it), whereas candidates who were on the wait list and eventually received offers would have a larger value for this parameter.\n\nnormdecidedate::Union{Missing, Float32}\nNormalized date at which the applicant replied with a decision. This uses the same scale as normofferdate. Consequently, an applicant who decided almost immediately would have a normdecidedate shortly after the normofferdate, whereas a candidate who decided on the final day will have a value of 1.0.\nUse missing if the applicant has not yet decided.\n\naccept::Union{Missing, Bool}\ntrue if the applicant accepted our offer, false if not. Use missing if the applicant has not yet decided.\n\n\n\n\n\n","category":"type"},{"location":"#AdmissionsSimulation.NormalizedApplicant-Tuple{}","page":"Home","title":"AdmissionsSimulation.NormalizedApplicant","text":"normapp = NormalizedApplicant(; program, rank=missing, offerdate, decidedate=missing, accept=missing, program_history)\n\nCreate an applicant from \"natural\" units, where rank is an integer and dates are expressed in Date format. Some are required (those without a default value), others are optional:\n\nprogram: a string encoding the program\nrank::Int: the rank of the applicant compared to other applicants to the same program in the same season.  Use 1 for the top candidate; the bottom candidate should have rank equal to the number of applications received.\nofferdate: the date on which an offer was (or might be) extended. E.g., Date(\"2021-01-13\").\ndecidedate: the date on which the candidate replied with a verdict, or missing\naccept: true if the candidate accepted our offer, false if it was turned down, missing if it is unknown.\n\nprogram_history should be a dictionary mapping ProgramKeys to ProgramData.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.Outcome","page":"Home","title":"AdmissionsSimulation.Outcome","text":"Outcome(ndeclines, naccepts)\n\nTally of the number of declines and accepts for offers of admission.\n\n\n\n\n\n","category":"type"},{"location":"#AdmissionsSimulation.ProgramData","page":"Home","title":"AdmissionsSimulation.ProgramData","text":"ProgramData stores summary data for a particular program and admissions season.\n\ntarget_raw::Int64\nThe target number of matriculants, based on applicant pool and training capacity.\n\ntarget_corrected::Int64\nThe actual target, correcting for over- or under-recruitment in previous years.\n\nnmatriculants::Union{Missing, Int64}\nThe number of matriculated students, or missing.\n\nnapplicants::Int64\nThe number of applicants received.\n\nfirstofferdate::Dates.Date\nThe date on which the first offer was made, essentially the beginning of the decision period for the applicants.\n\nlastdecisiondate::Dates.Date\nThe date on which all applicants must have rendered a decision, or the offer expires.\n\n\n\n\n\n","category":"type"},{"location":"#AdmissionsSimulation.ProgramKey","page":"Home","title":"AdmissionsSimulation.ProgramKey","text":"ProgramKey stores the program name and admissions season.\n\nprogram::String\nThe program abbreviation. AdmissionsSimulation.program_lookups contains the list of valid choices, together will full names.\n\nseason::Int16\nThe enrollment year. This is the year in which the applicant's decision was due. E.g., if the last date was April 15th, 2021, this would be 2021.\n\n\n\n\n\n","category":"type"},{"location":"#AdmissionsSimulation.ProgramYieldPrediction","page":"Home","title":"AdmissionsSimulation.ProgramYieldPrediction","text":"ProgramYieldPrediction records mid-season predictions and data for a particular program.\n\nnmatriculants::Measurements.Measurement{Float32}\nThe predicted number of matriculants.\n\npriority::Float32\nThe program's priority for receiving wait list offers. The program with the highest priority should get the next offer. Priority is computed as deficit/stddev, where deficit is the predicted undershoot (which might be negative if the program is predicted to overshoot) and stddev is the square root of the target (Poisson noise). Thus, programs are prioritized by the significance of the deficit.\n\npoutcome::Union{Missing, Float32}\nThe two-tailed p-value of the actual outcome (if supplied). This includes the effects of any future wait-list offers.\n\n\n\n\n\n","category":"type"},{"location":"#AdmissionsSimulation.cached_similarity-Tuple{Any, Any}","page":"Home","title":"AdmissionsSimulation.cached_similarity","text":"fsim = cached_similarity(σsel, σyield; offerdata, yielddata)\n\nCache the result of program_similarity, creating a function fsim(program1::AbstractString, program2::AbstractString) to compute the similarity between program1 and program2.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.match_function-Tuple{}","page":"Home","title":"AdmissionsSimulation.match_function","text":"fmatch = match_function(; σr=Inf32, σt=Inf32, progsim=default_similarity)\n\nGenerate a matching function comparing two applicants.\n\nfmatch(template::NormalizedApplicant, applicant::NormalizedApplicant, tnow::Union{Real,Missing})\n\nwill return a number between 0 and 1, with 1 indicating a perfect match. template is the applicant you wish to find a match for, and applicant is a candidate match. tnow is used to exclude applicants who had already decided by tnow.\n\nThe parameters of fmatch are determined by criteria:\n\nσr: the standard deviation of normrank (use Inf or missing if you don't want to consider rank in matches)\nσt: the standard deviation of normofferdate (use Inf or missing if you don't want to consider offer date in matches)\nprogsim: a function progsim(program1, program2) computing the \"similarity\" between programs. See cached_similarity. The default returns true if program1 == program2 and false otherwise.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.match_likelihood-Tuple{Function, AbstractVector{NormalizedApplicant}, NormalizedApplicant, Dates.Date}","page":"Home","title":"AdmissionsSimulation.match_likelihood","text":"likelihood = match_likelihood(fmatch, past_applicants, applicant, tnow::Date; program_history)\n\nUse this format if supplying tnow in Date format.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.match_likelihood-Tuple{Function, AbstractVector{NormalizedApplicant}, NormalizedApplicant, Real}","page":"Home","title":"AdmissionsSimulation.match_likelihood","text":"likelihood = match_likelihood(fmatch::Function,\n                              past_applicants::AbstractVector{NormalizedApplicant},\n                              applicant::NormalizedApplicant,\n                              tnow::Real)\n\nCompute the likelihood among past_applicants for matching applicant. tnow is the current date in normalized form (see normdate), and is used to exclude previous applicants who had already made a decision by tnow.\n\nSee also: match_function, select_applicant.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.matriculation_probability-Tuple{Any, Any}","page":"Home","title":"AdmissionsSimulation.matriculation_probability","text":"p = matriculation_probability(likelihood, past_applicants)\n\nCompute the probability that applicants weighted by likelihood would matriculate into the program, based on the choices made by past_applicants.\n\nlikelihood can be computed by match_likelihood.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.net_loglike-NTuple{4, AbstractVector{T} where T}","page":"Home","title":"AdmissionsSimulation.net_loglike","text":"net_loglike(σsels::AbstractVector, σyields::AbstractVector, σrs::AbstractVector, σts::AbstractVector;\n            applicants, program_history)\n\nCompute the prediction accuracy using historical data. For each year in program_history other than the earliest, use prior data to predict the probability of matriculation for each applicant.\n\nThe σ lists contain the values that will be used to compute accuracy; the return value is a 4-dimensional array evaluating the net log-likelihood for all possible combinations of these parameters. σsel and σyield will be used by cached_similarity to determine program similarity; σr and σs will be used to measure applicant similarity.\n\nTuning essentially corresponds to picking the index of the entry of the return value and then setting each parameter accordingly:\n\nnp = net_loglike(σsels, σyields, σrs, σts; applicants, program_history)\nidx = argmax(np)\nσsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.net_loglike-NTuple{4, Real}","page":"Home","title":"AdmissionsSimulation.net_loglike","text":"net_loglike(σsel::Real, σyield::Real, σr::Real, σt::Real;\n            applicants, past_applicants, offerdata, yielddata,\n            minfrac=0.01)\n\nCompute the net log-likelihood for a list of applicants' matriculation decisions. This function is used to evaluate the accuracy of predictions made by specific model parameters.\n\nFor applicant j with matriculation probability pⱼ, the net log-likelihood gets a contribution of +log(pⱼ) if the applicant accepted our offer of admission, and a contribution of -log(pⱼ) if the applicant declined. Consequently, this rewards predictions that accurately push pⱼ towards the extremes of 1 and 0.\n\nThe σ arguments are matching parameters, see program_similarity and match_function. offerdata and yielddata are computed by functions of the same name. minfrac expresses the minimum fraction of past_applicants allowed to be matched; any test_applicant matching fewer than these (in the sense of the sum of likelihoods computed by match_likelihood) leads to a return value of -Inf.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.normdate-Tuple{Dates.Date, ProgramData}","page":"Home","title":"AdmissionsSimulation.normdate","text":"normdate(t::Date, pdata::ProgramData)\n\nExpress t as a fraction of the gap between the first offer date and last decision date as stored in pdata (see ProgramData).\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.offerdata-Tuple{Any, Any}","page":"Home","title":"AdmissionsSimulation.offerdata","text":"offerdata(applicants, program_history)\n\nSummarize application and offer data for each program. The output is a dictionary mapping programname => (noffers, napplicants). The program selectivity is the ratio noffers/napplicants.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.program_similarity-Tuple{AbstractString, AbstractString}","page":"Home","title":"AdmissionsSimulation.program_similarity","text":"program_similarity(program1::AbstractString, program2::AbstractString;\n                   σsel=Inf32, σyield=Inf32, offerdata, yielddata)\n\nCompute the similarity between program1 and program2, based on selectivity (fraction of applicants who are admitted) and yield (fraction of offers that get accepted). The similarity ranges between 0 and 1, with 1 corresponding to identical programs.\n\nThe keyword arguments are the parameters controlling the similarity computation. offerdata and yielddata are the outputs of two functions of the same name (offerdata and yielddata). σsel and σyield are the standard deviations of selectivity and yield. The similarity is computed as\n\nexpleft(-frac(s₁ - s₂)²2σ_textsel² - frac(y₁ - y₂)²2σ_textyield²right)\n\nThe output of this function can be cached with cached_similarity.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.read_applicant_data-Tuple{AbstractString}","page":"Home","title":"AdmissionsSimulation.read_applicant_data","text":"past_applicants = read_applicant_data(filename; program_history)\n\nRead past applicant data from a file. See \"/home/runner/work/AdmissionsSimulation.jl/AdmissionsSimulation.jl/src/test/data/applicantdata.csv\" for an example of the format.\n\nThe second form allows you to transform each row with f(row) before extracting the data. This allows you to handle input formats that differ from the default.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.read_program_history-Tuple{AbstractString}","page":"Home","title":"AdmissionsSimulation.read_program_history","text":"program_history = read_program_history(filename)\n\nRead program history from a file. See \"/home/runner/work/AdmissionsSimulation.jl/AdmissionsSimulation.jl/src/test/data/programdata.csv\" for an example of the format.\n\nThe second form allows you to transform each row with f(row) before extracting the data. This allows you to handle input formats that differ from the default.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.run_simulation","page":"Home","title":"AdmissionsSimulation.run_simulation","text":"nmatriculants = run_simulation(pmatrics::AbstractVector, nsim::Int=100)\n\nGiven a list of candidates each with probability of matriculation pmatrics[i], perform nsim simulations of their admission decisions and compute the total number of matriculants in each simulation.\n\n\n\n\n\n","category":"function"},{"location":"#AdmissionsSimulation.select_applicant-Tuple{Any, Any}","page":"Home","title":"AdmissionsSimulation.select_applicant","text":"past_applicant = select_applicant(clikelihood, past_applicants)\n\nSelect a previous applicant from among past_applicants, using the cumulative likelihood clikelihood. This can be computed as cumsum(likelihood), where likelihood is computed by match_likelihood.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.wait_list_analysis-Tuple{Function, AbstractVector{NormalizedApplicant}, AbstractVector{NormalizedApplicant}, Union{Dates.Date, Real}}","page":"Home","title":"AdmissionsSimulation.wait_list_analysis","text":"nmatric, progstatus = wait_list_analysis(fmatch::Function,\n                                         past_applicants::AbstractVector{NormalizedApplicant},\n                                         applicants::AbstractVector{NormalizedApplicant},\n                                         tnow::Date;\n                                         program_history,\n                                         actual_yield=nothing)\n\nCompute the estimated number nmatric of matriculants and the program-specific yield prediction and wait-list priority, progstatus. progstatus is a mapping progname => progyp::ProgramYieldPrediction (see ProgramYieldPrediction).\n\nThe arguments are similarly to match_likelihood. If you're doing a post-hoc analysis, actual_yield can be a Dict(progname => nmatric), in which case the p-value for the observed outcome will also be stored in progstatus.\n\n\n\n\n\n","category":"method"},{"location":"#AdmissionsSimulation.yielddata-Union{Tuple{Y}, Tuple{Type{Y}, Any}} where Y<:Union{Outcome, Tuple{Outcome, Vararg{Outcome, N} where N}}","page":"Home","title":"AdmissionsSimulation.yielddata","text":"yielddata(Outcome, applicants)\nyielddata(Tuple{Outcome,Outcome,Outcome}, applicants)\n\nCompute the outcome of offers of admission for each program. applicants should be a list of NormalizedApplicant. The first form computes the Outcome for the entire season, and the second breaks the season up into epochs of equal duration and computes the outcome for each epoch separately. If provided, program_similarity will make use of the time-dependence of the yield.\n\n\n\n\n\n","category":"method"}]
}
