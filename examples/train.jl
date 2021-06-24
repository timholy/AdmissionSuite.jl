# Settings & utilities for model-training

substnan(A) = [isnan(a) ? oftype(a, -Inf) : a for a in A]

# Note the more combinations, the longer it takes
# Starting big and going small works with how argmax handles ties
σsels = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σyields = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σrs = Float32[Inf, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
σts = Float32[Inf, 1.0, 0.5, 0.2, 0.1]
