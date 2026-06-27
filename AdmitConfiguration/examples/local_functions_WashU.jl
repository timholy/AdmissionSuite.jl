getaccept(row) = getaccept(row."Final Outcome")
getaccept(::Missing) = missing
function getaccept(choice::AbstractString)
    if choice ∈ ("Class Member", "Deferred")
        return true
    elseif choice ∈ ("Declined", "Interviewed, Reject", "Withdrew Following Interview")
        return false
    end
    return missing
end

function getdecidedate(row)
    acc = getaccept(row)
    if acc === true
        # return todate_or_missing(row."Class Member Date")
        return todate_or_missing(row."Class Member")
    elseif acc === false
        rawdate = row."Declined"
        # In real applications we know these columns exist (the `hasproperty` checks always return `true`),
        # but the WashU config is also used for testing and some of the fake data sets don't set these columns.
        # For your own institution, you probably don't need the `hasproperty` checks.
        if (ismissing(rawdate) || isempty(rawdate)) && hasproperty(row, "Interviewed, Reject")
            rawdate = row."Interviewed, Reject"
        end
        if (ismissing(rawdate) || isempty(rawdate)) && hasproperty(row, "Withdrew Following Interview")
            rawdate = row."Withdrew Following Interview"
        end
        return todate_or_missing(rawdate)
    end
    return missing
end

when_updated(row) = (row."Stage Date")::DateTime
