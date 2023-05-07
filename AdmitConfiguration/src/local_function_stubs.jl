# Locally-defined functions
# These require so much flexibility it is better to define them through code
# These are just stubs that allow us to assign a docstring

"""
    getaccept(row)

Return
    - `true` if the applicant has accepted an offer of admission
    - `false` if the applicant is no longer a candidate for admission
    - `missing` if the applicant is a candidate but the decision is unknown

A `getaccept` function can be omitted if your database has a column containing this information
(see [`set_column_configuration`](@ref) for `"accept"`).

# Example

Suppose your table has a column called "Outcome" which takes values "Accept", "Decline", "Reject",
or "Withdrew". Then in simplest form you could implement this function as:

```
getaccept(row) = row."Outcome" == "Accept"
```

A better implementation might allow the "Outcome" field to be blank, returning `missing` in that case:

```julia
function getaccept(row)
    outcome = row."Outcome"
    (ismissing(outcome) || isempty(outcome)) && return missing
    return outcome == "Accept"
end
```

Even more sophisticated implementations might check for unexpected values and throw an error if they are encountered.
"""
function getaccept end

"""
    getdecidedate(row)

Return the date on which the verdict for the applicant in `row` (a row of the applicant table) was determined.
This might be the date where they either accepted an offer, were rejected, or withdrew their application.

A `getdecidedate` function can be omitted if your database has a column containing this information
(see [`set_column_configuration`](@ref) for `"decide date"`).

# Example

Suppose your table has a column called "Date of verdict", in which case implementing this would be as simple as

```
getdecidedate(row) = row."Date of verdict"
```

In contrast, supposed you have multiple columns, "Date of accept", "Date of decline", "Date of withdrawal", of
which only one has an entry.  Then this might be implemented as

```
function getdecidedate(row)
    if !ismissing(row."Date of accept")
        return row."Date of accept"
    elseif !ismissing(row."Date of decline")
        return row."Date of decline"
    elseif !ismissing(row."Date of withdrawal")
        return row."Date of withdrawal"
    else
        error("expected one of the accept/decline/withdrawal dates to be specified")
    end
end
```
"""
function getdecidedate end

"""
    when_updated(row)

Return date (or date and time) at which a record `row` was updated in the database.
Required for de-duplicating database entries in `Admit.keep_final_records`.
"""
function when_updated end
