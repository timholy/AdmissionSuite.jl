# Locally-defined functions
# These require so much flexibility it is better to define them through code
# These are just stubs that allow us to assign a docstring

"""
    getaccept(row)

Return `true` or `false` depending on whether the applicant in `row` (a row of the applicant table)
accepted the offer of admission.

# Example

Suppose your table has a column called "Outcome" which takes values "Accept", "Decline", "Reject",
or "Withdrew". Then in simplest form you could implement this function as:

```
getaccept(row) = row."Outcome" == "Accept"
```

More sophisticated implementations might check for unexpected values and throw an error if they are encountered.
"""
function getaccept end

"""
    getdecidedate(row)

Return the date on which the applicant in `row`  (a row of the applicant table) informed admissions
about their decision about whether to accept the offer of admission.

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
