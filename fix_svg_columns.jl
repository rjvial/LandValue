################################################################################
#                    SCRIPT - FIX SVG COLUMNS                                  #
################################################################################

using JSON
using LandValue, DotEnv, DataFrames

TABLE_NAME = "tabla_resultados_optimizacion"

function parse_vec_ps_opt(str::String)::Vector{PolyShape}
    if isempty(str) || str == "missing"
        return PolyShape[]
    end

    result = PolyShape[]

    matrix_pattern = r"\[([0-9][0-9\.\-e\+\s;]+)\]"

    for mat_match in eachmatch(matrix_pattern, str)
        mat_str = mat_match.captures[1]
        rows = split(mat_str, ";")
        n_rows = length(rows)
        if n_rows < 3
            continue
        end

        first_row = parse.(Float64, split(strip(rows[1])))
        n_cols = length(first_row)
        if n_cols < 2
            continue
        end

        mat = Matrix{Float64}(undef, n_rows, n_cols)
        for (i, row) in enumerate(rows)
            vals = parse.(Float64, split(strip(row)))
            mat[i, :] = vals
        end

        ps = PolyShape([mat], 1)
        push!(result, ps)
    end

    return result
end

function generate_svg_from_vec_ps(vec_ps::Vector{PolyShape})::String
    if isempty(vec_ps)
        return ""
    end

    return polyShape.planta2svg(vec_ps)
end


my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

println("Starting SVG column generation...")

println("Adding SVG columns if they don't exist...")
alter_query_1 = "ALTER TABLE $TABLE_NAME ADD COLUMN IF NOT EXISTS svg_planta_primer_piso TEXT"
alter_query_2 = "ALTER TABLE $TABLE_NAME ADD COLUMN IF NOT EXISTS svg_planta_pisos_superiores TEXT"
pg_julia.query(conn, alter_query_1)
pg_julia.query(conn, alter_query_2)
println("  ✓ Columns ready")

query = "SELECT id_opti, proyecto_vec_ps_opt FROM $TABLE_NAME ORDER BY id_opti"

df = pg_julia.query(conn, query)

total_rows = size(df, 1)
println("Found $total_rows rows to process")

for i in 1:total_rows
    row_id = df.id_opti[i]
    println("\nProcessing row $i/$total_rows (id_opti=$row_id)...")

    vec_ps_str = string(df.proyecto_vec_ps_opt[i])
    vec_ps = parse_vec_ps_opt(vec_ps_str)

    svg_planta = generate_svg_from_vec_ps(vec_ps)
    svg_planta_primer_piso = svg_planta
    svg_planta_pisos_superiores = svg_planta

    svg_file_path = "svg_planta_primer_piso.svg"
    open(svg_file_path, "w") do f
        write(f, svg_planta_primer_piso)
    end
    svg_file_path = "svg_planta_pisos_superiores.svg"
    open(svg_file_path, "w") do f
        write(f, svg_planta_pisos_superiores)
    end

    svg_primer_escaped = replace(svg_planta_primer_piso, "'" => "''")
    svg_superior_escaped = replace(svg_planta_pisos_superiores, "'" => "''")

    update_query = """
    UPDATE $TABLE_NAME
    SET
        svg_planta_primer_piso = '$svg_primer_escaped',
        svg_planta_pisos_superiores = '$svg_superior_escaped'
    WHERE id_opti = $row_id
    """

    pg_julia.query(conn, update_query)

    println("  ✓ Updated row $row_id")
end

println("\n✓ Successfully processed $total_rows rows")
