# This is a partial configuration (omitting some details of the SQL configuration, see `set_sql_queries` and `set_dsn`)
# It is used for some of the tests
using AdmitConfiguration
using CSV
set_programs(joinpath(@__DIR__, "WashU.csv"))
set_local_functions(joinpath(@__DIR__, "local_functions_WashU.jl"))
set_column_configuration(# Applicant table
                         "name" => "Applicant",
                         "app program" => "program_interest",
                         "app season" => "enrollment_year",
                         "offer date" => "Accept Offered Date",
                         # Program table
                         "prog program" => "program_interest",
                         "prog season" => "year",
                         "slots" => "Matric Target",
                         # napplicants not present
                         # nmatriculants not present
)