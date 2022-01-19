function getaccept(row)
    choice = row."Final Outcome"
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
        return todate_or_missing(row."Declined Date")
    end
    return missing
end

when_updated(row) = (row."Stage Date")::DateTime
