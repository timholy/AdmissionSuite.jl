# Types for determining targets

# A list of pairs
const ListPairs{K,V} = Union{AbstractDict{K,V},AbstractVector{Pair{K,V}}}

"""
`Service` measures the service contributions of a particular faculty member to a particular program.

$(TYPEDFIELDS)
"""
struct Service
    """
    The number of admissions interviews conducted for that program, typically over a fixed time window.
    """
    ninterviews::Float32

    """
    The number of thesis committees served on for that program, typically over a fixed time window.
    """
    ncommittees::Float32
end
Service() = Service(0, 0)
Base.:+(a::Service, b::Service) = Service(a.ninterviews + b.ninterviews, a.ncommittees + b.ncommittees)
Base.:/(s::Service, r::Real) = Service(s.ninterviews/r, s.ncommittees/r)
# Estimate the total commitment (interview = 1hr; thesiscmtee = 5 committee meetings/student, 2hrs each)
total(fi::Service) = fi.ninterviews + 10*fi.ncommittees

"""
`ServiceCalibration` is meant to standardize forms of service to account for the fact that young programs
may not have students in thesis committees and therefore don't have as much service per faculty member.
"""
struct ServiceCalibration
    """
    The average number of committees per interview for well-established programs.
    """
    c_per_i::Float32

    """
    The conversion factor from a "service unit" `max(c_per_i * i, c)` to hours of service.
    """
    t_per_u::Float32
end
total(s::Service, sc::ServiceCalibration) = sc.t_per_u * max(sc.c_per_i * s.ninterviews, s.ncommittees)

"""
`FacultyRecord` stores the program affiliations and service contributions of a particular faculty member.

$(TYPEDFIELDS)
"""
struct FacultyRecord
    """
    Date on which the faculty member was approved to train students in any program
    """
    start::Date

    """
    Program affiliations, in decreasing order of importance (e.g., primary, secondary, ...)
    """
    programs::Vector{String}

    """
    `program=>Service` contributions (to any program, not just those listed in `programs`)
    """
    service::Vector{Pair{String,Service}}
end
years(fr::FacultyRecord, yr=year(today())) = yr - year(fr.start) + 1
