using JSON
using LandValue, DotEnv, DataFrames


TABLE_NAME = "tabla_resultados_optimizacion"

function extract_first_geometry(old_json_str::String)::String
    if isempty(old_json_str)
        return ""
    end

    old_obj = JSON.parse(old_json_str)

    if haskey(old_obj, "geometries") && !isempty(old_obj["geometries"])
        geometry = old_obj["geometries"][1]

        geometry["metadata"] = Dict{String,Any}(
            "version" => 4.5,
            "type" => "BufferGeometry",
            "generator" => "LandValue.polyShape"
        )

        return JSON.json(geometry)
    end

    return ""
end

function combine_geometries(old_json_str::String)::String
    if isempty(old_json_str)
        return ""
    end

    old_obj = JSON.parse(old_json_str)

    if !haskey(old_obj, "geometries") || isempty(old_obj["geometries"])
        return ""
    end

    all_vertices = Float64[]
    all_indices = Int[]

    for geometry in old_obj["geometries"]
        if !haskey(geometry, "data")
            continue
        end

        data = geometry["data"]

        if haskey(data, "attributes") && haskey(data["attributes"], "position")
            vertices = data["attributes"]["position"]["array"]
            vertex_offset = div(length(all_vertices), 3)

            append!(all_vertices, vertices)

            if haskey(data, "index")
                indices = data["index"]["array"]
                for idx in indices
                    push!(all_indices, idx + vertex_offset)
                end
            end
        end
    end

    if isempty(all_indices)
        return ""
    end

    geometry_uuid = string(Base.UUID(rand(UInt128)))

    geometry = Dict{String,Any}(
        "uuid" => geometry_uuid,
        "type" => "BufferGeometry",
        "data" => Dict{String,Any}(
            "attributes" => Dict{String,Any}(
                "position" => Dict{String,Any}(
                    "itemSize" => 3,
                    "type" => "Float32Array",
                    "array" => all_vertices
                )
            ),
            "index" => Dict{String,Any}(
                "type" => "Uint16Array",
                "array" => all_indices
            )
        ),
        "metadata" => Dict{String,Any}(
            "version" => 4.5,
            "type" => "BufferGeometry",
            "generator" => "LandValue.polyShape"
        )
    )

    return JSON.json(geometry)
end

function fix_json_columns(conn)
    println("Starting JSON column transformation...")

    query = "SELECT id_opti, json_deptos_opt, json_terrazas_opt, json_area_comun_opt, json_planta_primer_piso, json_planta_pisos_superiores FROM $TABLE_NAME"

    df = pg_julia.query(conn, query)

    total_rows = size(df, 1)
    println("Found $total_rows rows to process")

    for i in 2:total_rows
        row_id = df.id_opti[i]
        println("\nProcessing row $i/$total_rows (id_opti=$row_id)...")

        json_deptos_opt = extract_first_geometry(df.json_deptos_opt[i])
        json_terrazas_opt = extract_first_geometry(df.json_terrazas_opt[i])
        json_area_comun_opt = extract_first_geometry(df.json_area_comun_opt[i])
        json_planta_primer_piso = combine_geometries(df.json_planta_primer_piso[i])
        json_planta_pisos_superiores = combine_geometries(df.json_planta_pisos_superiores[i])

        json_deptos_escaped = replace(json_deptos_opt, "'" => "''")
        json_terrazas_escaped = replace(json_terrazas_opt, "'" => "''")
        json_area_comun_escaped = replace(json_area_comun_opt, "'" => "''")
        json_planta_primer_escaped = replace(json_planta_primer_piso, "'" => "''")
        json_planta_superior_escaped = replace(json_planta_pisos_superiores, "'" => "''")

        update_query = """
        UPDATE $TABLE_NAME
        SET
            json_deptos_opt = '$json_deptos_escaped',
            json_terrazas_opt = '$json_terrazas_escaped',
            json_area_comun_opt = '$json_area_comun_escaped',
            json_planta_primer_piso = '$json_planta_primer_escaped',
            json_planta_pisos_superiores = '$json_planta_superior_escaped'
        WHERE id_opti = $row_id
        """

        pg_julia.query(conn, update_query)

        println("  ✓ Updated row $row_id")
    end

    println("\n✓ Successfully processed $total_rows rows")
end

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

try
    fix_json_columns(conn)
finally
    close(conn)
end
