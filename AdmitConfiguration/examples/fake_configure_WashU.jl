# This is a partial configuration (omitting some details of the SQL configuration, see `set_sql_queries` and `set_dsn`)
# It is used for some of the tests
if isdefined(@__MODULE__, :AdmissionSuite)
    using AdmissionSuite.AdmitConfiguration
else
    using AdmitConfiguration
    using CSV
end
set_programs(joinpath(@__DIR__, "WashU.csv"))
set_local_functions(joinpath(@__DIR__, "local_functions_WashU.jl"))
set_column_configuration(# Applicant table
                         "name" => "Applicant",
                         "app program" => "program_interest",
                         "app season" => "enrollment_year",
                         "offer date" => "Acceptance Offered Date",
                         # Program table
                         "prog program" => "program_interest",
                         "prog season" => "enrollment_year",
                         "slots" => "Matric Target",
                         "napplicants" => "Total Applicants",
                         # nmatriculants not present
)
set_date_format("y-m-d H:M:S.s")
