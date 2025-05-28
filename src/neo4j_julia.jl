module neo4j_julia

using DotEnv, AWS, DataFrames, CSV

function connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

    conn = Dict(
    "neo4j_host" => neo4j_host, #"bolt://localhost:7687",
    "neo4j_user" => neo4j_user, #"neo4j",
    "neo4j_password" => neo4j_password, #"x67y1332",
    "folder" =>  folder, #"/usr/bin/cypher-shell",
    "key_pair"   => key_pair, #"neo4j-key-pair.pem",
    "ec2_user"   => ec2_user, #"ec2-user",
    "public_dns" => public_dns 
    )
    
    return conn
end

function cypher_to_dataframe(query::AbstractString, conn::Dict{String,String})
    # 1) collapse newlines into spaces so your MATCH … RETURN stays one argument
    # cleaned = replace(query, '\n' => ' ')

    neo4j_host = conn["neo4j_host"]
    neo4j_user = conn["neo4j_user"]
    neo4j_password = conn["neo4j_password"]
    folder = conn["folder"]
    key_pair = conn["key_pair"]
    ec2_user = conn["ec2_user"]
    public_dns = conn["public_dns"]

    # Build the SSH command that runs cypher-shell remotely without encryption
    ssh_cmd = `ssh -i $key_pair -o StrictHostKeyChecking=no $ec2_user@$public_dns $folder \
    -a $neo4j_host \
    --encryption false \
    -u $neo4j_user -p $neo4j_password \
    --format plain`

    # Pipe the query and capture output
    output = read(pipeline(ssh_cmd; stdin=IOBuffer(query)), String)

    io = IOBuffer(output)
    df = CSV.read(io, DataFrame; normalizenames=true)
    
    return df
end

export connection, cypher_to_dataframe

end