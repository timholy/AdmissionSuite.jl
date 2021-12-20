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
using AdmitConfiguration
using CSV
setprograms("/path/to/saved/file.csv")  # replace this with the specific path to your CSV file
```

You are now done configuring your programs.
