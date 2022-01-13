```@meta
CurrentModule = AdmitConfiguration
```

# AdmitConfiguration

## Configuring your programs

!!! info
    This step only needs to be performed once when you first use `Admit` or `AdmissionTargets`.
    If you restructure your programs, you'll want to reconfigure to match the current programs.

Using a spreadsheet program, create a table that, at a minimum, has a single column called `Abbreviation` and more comprehensively may have some or all of the following columns:

![programs](assets/programs.png)

The `Abbreviation` column must list all your programs. This should be whatever "tag" you like to use to refer to each program, and should not be too long as it will need to fit in dropdown boxes in `Admit`. Full names can optionally be listed in `ProgramName`, and indeed this must be set if your database stores records by full program names. For the remaining columns, see the documentation on [`setprograms`](@ref).  If you need a complete example, see the file `examples/WashU.csv` within this package repository.

Once done, save the table in [Comma-separated value (CSV) format](https://en.wikipedia.org/wiki/Comma-separated_values) using your spreadsheet program's "Save as" or "Export" functionality. Then, in Julia execute the following set of statements:

```julia
using AdmissionSuite, AdmitConfiguration
using CSV
setprograms("/path/to/saved/file.csv")  # replace this with the specific path to your CSV file
```

You are now done configuring your programs.

## Configuring database access

`Admit` can directly query applicant records through a SQL interface. This has been tested on Windows and Linux, but may work with small modifications on Mac.

To use this feature, several configuration steps are required. Most of these may not be necessary if you are running Admit from a machine that can already access your database.

### [If your machine already has access to the database](@id conncheck)

If your system can already access the SQL database via a "data source" (DSN), just check whether you have access from Julia:

```
julia> using AdmissionSuite, Admit

julia> conn = connectdsn(<dsnname>)
```

where you replace `<dsnname>` with the name of your DSN (for example, `connectdsn("DBBS")` if you've created a DSN called "DBBS"). This will prompt you for your user name and password before attempting to connect to the SQL server.
If this returns without an obvious error, all is well and you can skip below to the section on [setting up automatic connections](@ref automatic).

!!! warning
    While it's possible to store your username and password in your DSN configuration, this is a [security hole](https://www.microsoft.com/en-us/microsoft-365/blog/2011/04/08/power-tip-improve-the-security-of-database-connections/) and not recommended.
    For this reason, `Admit` will always prompt you for your user name and password.

If you do not already have access via a DSN, the next sections describe how to configure it.

### [Installing an ODBC driver](@id driver)

If necessary, install the [SQL Server ODBC driver](https://docs.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server).

#### Windows



#### Other platforms

- From the [link above](@ref driver), download the MSODBC package for your platform and install it
- Find the library file on your system
- Start Julia and execute the following:

```julia
julia> using AdmissionSuite

julia> libpath = "/opt/microsoft/msodbcsql17/lib64/libmsodbcsql-17.4.so.1.1"

julia> ODBC.adddriver("MSODBC", libpath)
```

where `libpath` should be the path to the library on your own system. Library files have `dll`, `dylib`, or `so` in their extension.

Now `"MSODBC"` is a shortcut for the actual driver library.

### Option 1: configuring the Data Source (DSN)

Use either a DSN or a connection string; the two are nearly equivalent except for minor differences in syntax.

#### From within the ODBC configuration utility (Windows)



#### From within Julia

This approach can be used on non-Windows platforms. After [installing the driver](@ref driver), execute

```julia
julia> using AdmissionSuite    # not needed if you've already done this in the same session

julia> ODBC.adddsn(<dsnname>, "MSODBC"; SERVER=<SQL server URL>, DATABASE=<database name>)
```

The items between `<>` are items you need to fill in. For example, for WashU's DBBS the line looks something like this:

```julia
julia> ODBC.adddsn("DBBS", "MSODBC"; SERVER="someurl.wustl.edu", DATABASE="DBBS")
```

Now, `<dnsname>` (`"DBBS"` in the example above) is a shortcut for the DSN.

!!! warning
    Putting your user name and password into the DSN configuration is a [security hole](https://www.microsoft.com/en-us/microsoft-365/blog/2011/04/08/power-tip-improve-the-security-of-database-connections/) and not recommended.

#### Checking your setup

Check your connection described [above](@ref conncheck).

### Option 2: using a connection string

!!! warning
    Probably delete this section

As an alternative, you can use a full connection string. After [adding a driver](@ref driver), launch Julia and execute

```julia
julia> using AdmissionSuite

julia> conn = conn = ODBC.Connection("Driver=MSODBC;SERVER=<SQL server URL>;DATABASE=<database name>)
```

where `<>` are meant to be filled in for your local configuration. For example, for WashU's DBBS this would start

```julia
julia> conn = ODBC.Connection("Driver=MSODBC;SERVER=someurl.wustl.edu;DATABASE=DBBS;UID=...")
```


### [Making your connection automatic](@id automatic)

If you have a DSN, use

```julia
julia> using AdmissionSuite, AdmitConfiguration

julia> setdsn(<dnsname>)
```

Henceforth `Admit` will connect to the database as needed, all you have to do is respond to password prompts.

If you instead connect with a connect string, change the previous line to

```julia
julia> setconnect("Driver=MSODBC;SERVER=...")
```

with the connect string you verified above.  [`setdsn`](@ref) and its alternative [`setconnect`](@ref) saves your local configuration so that it gets loaded automatically every time you start `AdmissionSuite`.
