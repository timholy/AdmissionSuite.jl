function getaccept(row)
    choice = row."Final Outcome"
    if choice ∈ ("Class Member", "Deferred")
        return true
    elseif choice ∈ ("Declined", "Interviewed, Reject", "Withdrew Following Interview")
        return false
    end
    error("unrecognized choice ", choice)
end

function getdecidedate(row)
    if getaccept(row)
        return todate_or_missing(row."Class Member")
    end
    return todate_or_missing(row."Declined")
end
