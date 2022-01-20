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
        return todate_or_missing(row."Class Member Date")
    elseif acc === false
        return todate_or_missing(row."Declined Date")
    end
    return missing
end

when_updated(row) = (row."Stage Date")::DateTime
