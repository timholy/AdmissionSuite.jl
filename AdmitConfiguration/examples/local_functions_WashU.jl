getaccept(row) = getaccept(row."Current/Final Stage")
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
        return todate_or_missing(row."Class Member Date")
    elseif acc === false
        rawdate = row."Declined Date"
        # In real applications we know these columns exist (the `hasproperty` checks always return `true`),
        # but the WashU config is also used for testing and some of the fake data sets don't set these columns.
        # For your own institution, you probably don't need the `hasproperty` checks.
        if (ismissing(rawdate) || isempty(rawdate)) && hasproperty(row, "Interviewed, Reject Date")
            rawdate = row."Interviewed, Reject Date"
        end
        if (ismissing(rawdate) || isempty(rawdate)) && hasproperty(row, "Withdrew Following Interview Date")
            rawdate = row."Withdrew Following Interview Date"
        end
        return todate_or_missing(rawdate)
    end
    return missing
end

when_updated(row) = (row."Stage Date")::DateTime
