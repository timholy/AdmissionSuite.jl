include("train.jl")

## Tune the matching function
lastyear = maximum(pk -> pk.season, keys(program_history))
test_applicants = filter(app->app.season == lastyear  && isa(app.normdecidedate, Real), applicants)
past_applicants = filter(app->app.season < lastyear && isa(app.normdecidedate, Real), applicants)

# First train without access to individual data (program-only data)
corarray_pg = match_correlation(σsels, σyields, [Inf32], [Inf32]; applicants=past_applicants, program_history)
idx_pg = argmax(substnan(corarray_pg))
σsel_pg, σyield_pg, σr_pg, σt_pg = σsels[idx_pg[1]], σyields[idx_pg[2]], Inf32, Inf32

# Now train with all data
corarray = match_correlation(σsels, σyields, σrs, σts; applicants=past_applicants, program_history)
idx = argmax(substnan(corarray))
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]
