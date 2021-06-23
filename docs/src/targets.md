# Calculating admission targets

Given a target total number of students, here the task is to allocate the number for each program.  We assign these based on two factors,  the number of applicants and the number of training faculty, with no attempt to give bonuses for "applicant quality" as this is difficult to measure in an unbiased way.

While the number of applicants is unambiguous, it is less straightforward to count faculty because they may participate in multiple programs.  There are two major categories of algorithms supported:
- counting faculty based on program affiliation (e.g., primary, secondary, and tertiary program affiliations for each faculty member, where secondary and tertiary are optional)
- counting faculty based on their training service, specifically in the forms of admissions interviews and thesis committees

Each category has multiple sub-options. Data for both is provided in the form of a [`FacultyRecord`](@ref).

Among the choices below, the recommended algorithm is called `NormEffort`.

## Faculty records

Faculty records are stored in the following format:

```jldoctest targets
julia> using AdmissionsSimulation, Dates

julia> facrecs = [
           "Last1, First1" => FacultyRecord(Date("2011-10-01"), ["BBSB", "CSB"], ["BBSB" => Service(11, 3), "MMMP" => Service(1, 0)]),
           "Last2, First2" => FacultyRecord(Date("2018-05-31"), ["EEPB", "CSB"], ["EEPB" => Service(8, 2)])
       ];
```

This records the date on which the faculty member became an active member of DBBS, the program affiliations, and the total [`Service`](@ref) to each program.  In the example above, both faculty members have a secondary affiliation with ["CSB"](https://dbbs.wustl.edu/divprograms/compbio/Pages/default.aspx) but neither has yet done service for the program.

Faculty records can be parsed from spreadsheets using [`read_faculty_data`](@ref).

## Affiliation-based measures

Affiliations are counted with [`faculty_affiliations`](@ref):

```jldoctest targets
julia> f = faculty_affiliations(facrecs, :primary)
Dict{String, Float32} with 2 entries:
  "EEPB" => 1.0
  "BBSB" => 1.0
```
The two faculty members had primary affiliations of BBSB and EEPB, respectively, so each gets counted as having one faculty member each; while two listed CSB as a secondary affiliation, with `:primary` these are not counted.

There are several other options, for example
```jldoctest targets
julia> f = faculty_affiliations(facrecs, :normalized)
Dict{String, Float32} with 3 entries:
  "EEPB" => 0.5
  "CSB"  => 1.0
  "BBSB" => 0.5
```
With `:normalized`, a faculty member with `n` affiliations contributes `1/n` to each.
Other options include `:all` and `:weighted`.

The recommended default is `:primary` because this is the only choice which yields consistent answers under program mergers and splits.

## Effort-based measures

The other main category of algorithm attempts to gauge capacity and enthusiasm for training based on actual service.  While the reliance on proven investment has several attractions,  it is worth noting that these algorithms can have the tendency to preserve any status quo since service opportunities are in proportion to the number of students.

To compute total faculty effort, we first compute an "effort matrix" for each faculty/program pair:

```jldoctest targets
julia> faculty, programs, E = faculty_effort(facrecs, 2016:2020);

julia> faculty
2-element Vector{String}:
 "Last1, First1"
 "Last2, First2"

julia> programs
3-element Vector{String}:
 "BBSB"
 "EEPB"
 "MMMP"

julia> E
2×3 Matrix{Float32}:
 8.19102   0.0     0.199781
 0.0      10.8034  0.0
```

`E[j,i]` corresponds to `faculty[j]` and `programs[i]`.

From here one can compute total number of faculty per program via [`faculty_involvement`](@ref):

```jldoctest targets
julia> f = faculty_involvement(E)
3-element Vector{Float32}:
 0.97619045
 1.0
 0.023809522
```

This essentially means that BBSB has 0.98 faculty members (98% of "Last1, First1"'s effort, in hours, went to BBSB), EEPB has 1 (based on "Last2, First2"), and MMMP has 0.02 (based on 2% of the effort of "Last1, First1").

This too has several options; `:normeffort` is the recommended default as the only choice that is invariant under program mergers and splits.

## Target computation

Having made a choice about how to assess the number of faculty, we can now compute the target number of "slots" (desired number of matriculants) per program:

```jldoctest targets
julia> targets(Dict("BBSB" => 86, "CSB" => 90, "EEPB" => 47, "MMMP" => 139), Dict(zip(programs, f)), 12)
Dict{String, Float32} with 4 entries:
  "EEPB" => 4.61209
  "CSB"  => 0.0
  "BBSB" => 6.16404
  "MMMP" => 1.22386
```

The first argument is the number of applicants per program.  In this simple example, `f` was computed from `faculty_involvement` and no faculty in our example list provided service to "CSB", so that program was awarded no slots.  Under more realistic circumstances with hundreds of faculty engaged in many different ways, the slot computation reflects the aggregate affiliations or involvement across programs.
