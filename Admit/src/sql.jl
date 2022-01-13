function query_applicants(conn)
    return DBInterface.execute(conn, "SELECT * FROM dbo.vw_interviewed_hold_outcome")|> DataFrame
end
