function connectdsn(dsnname = sql_dsn[]; usepasswd::Bool=false)
    if usepasswd
        user, password = getcredentials()
        return ODBC.Connection(dsnname; user, password)
    else
        ODBC.Connection(dsnname)
    end
end

if Sys.iswindows()
    function getcredentials()
	usr, buf = Base.winprompt("", "Authenticate for database access", "")
	return usr, read(buf, String)
    end
else
    function getcredentials()
        println("Authenticate for database access")
        user = Base.prompt("User name")
        passwd = Base.getpass("Password")
        return user, read(passwd, String)
    end
end
