substnan(A) = [isnan(a) ? oftype(a, -Inf) : a for a in A]

## Tune the matching function
lastyear = maximum(pk -> pk.season, keys(program_history))
test_applicants = filter(app->app.season == lastyear, applicants)
past_applicants = filter(app->app.season < lastyear, applicants)

# Note the more combinations, the longer it takes
# Starting big and going small works with how argmax handles ties
σsels = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σyields = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σrs = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σts = Float32[Inf, 1.0, 0.5, 0.2, 0.1]

# First train without access to individual data (program-only data)
corarray_pg = match_correlation(σsels, σyields, [Inf32], [Inf32]; applicants=past_applicants, program_history)
idx_pg = argmax(substnan(corarray_pg))
σsel_pg, σyield_pg, σr_pg, σt_pg = σsels[idx_pg[1]], σyields[idx_pg[2]], Inf32, Inf32

# Now train with all data
corarray = match_correlation(σsels, σyields, σrs, σts; applicants=past_applicants, program_history)
idx = argmax(substnan(corarray))
σsel, σyield, σr, σt = σsels[idx[1]], σyields[idx[2]], σrs[idx[3]], σts[idx[4]]
