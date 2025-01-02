module neo4j_julia

using DotEnv, AWS, DataFrames, CSV

function connection(neo4j_host, neo4j_user, neo4j_password)
    
    conn = Dict(
    "folder" => "C:\\Users\\rjvia\\.Neo4jDesktop\\relate-data\\dbmss\\dbms-8d2802c9-5882-41ce-a9e4-257030275495\\bin\\cypher-shell.bat",
    "host" => neo4j_host,
    "user" => neo4j_user,
    "password" => neo4j_password
    )   
    return conn
end

function cypher_to_dataframe(query, conn)
    query = replace(query, "\n" => "")
    cmd = `$(conn["folder"]) -a $(conn["host"]) --format plain -u $(conn["user"]) -p $(conn["password"]) $(query)`
    result = read(cmd, String)
    df = CSV.File(IOBuffer(result)) |> DataFrame
    rename!(df, Symbol.(replace.(String.(names(df)), " " => "")))
    return df
end

export connection, cypher_to_dataframe

end