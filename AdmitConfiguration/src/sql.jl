function connectdsn(dsnname = sql_dsn[])
    user, password = getcredentials()
    return ODBC.Connection(dsnname; user, password)
end

if Sys.iswindows()
    getcredentials() = Base.winprompt("", "Authenticate for database access", "")
else
    function getcredentials()
        println("Authenticate for database access")
        user = Base.prompt("User name")
        passwd = Base.getpass("Password")
        return user, passwd
    end
end
