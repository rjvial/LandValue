################################################################################
#                    SCRIPT 2A - VOLUMETRIC OPTIMIZATION                     #
################################################################################

using LandValue, DotEnv, LinearAlgebra, OrderedCollections

################################################################################
#                        DATABASE CONNECTION SETUP                           #
################################################################################

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"
key_pair = "neo4j-key-pair.pem"
ec2_user = "ec2-user"
public_dns = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)["dnsName"]
folder = "/usr/bin/cypher-shell"
conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

################################################################################
#                         3D VISUALIZATION SETTINGS                          #
################################################################################

fpe = FlagPlotEdif3D()
fpe.predio = true
fpe.volTeorico = true
fpe.volConSombra = true
fpe.edif = true
fpe.sombraVolTeorico_p = true
fpe.sombraVolTeorico_o = true
fpe.sombraVolTeorico_s = true
fpe.sombraEdif_p = true
fpe.sombraEdif_o = true
fpe.sombraEdif_s = true

################################################################################
#                          HELPER FUNCTIONS                                  #
################################################################################

function juliaTypeToPgType(juliaType::Type)
    if juliaType <: Integer
        return "int4"
    elseif juliaType <: AbstractFloat
        return "numeric(10,2)"
    elseif juliaType <: AbstractString
        return "text"
    elseif juliaType <: Bool
        return "boolean"
    else
        return "text"
    end
end

function dict2tablevec(dict, primaryKeyStr::String="id")
    vecColumnNames = [string(k) for k in keys(dict)]
    if !(primaryKeyStr in vecColumnNames)
        push!(vecColumnNames, primaryKeyStr)
    end
    vecColumnTypes = [juliaTypeToPgType(typeof(haskey(dict, col) ? dict[col] : 1)) for col in vecColumnNames]
    return vecColumnNames, vecColumnTypes
end

function processValue(value, dict_geom)
    if typeof(value) == Bool
        return value ? 1 : 0
    elseif isa(value, Tuple)
        tuple_str = string(value)
        tuple_str = replace(tuple_str, r"[\"'\[\](){}]" => " ")
        return strip(tuple_str)
    # elseif isa(value, PolyShape)
    #     shape_adjusted = polyShape.ajustaCoordenadasInversa(value, dict_geom["dx"], dict_geom["dy"])
    #     shape_4326 = polyShape.shape_32719to4326(shape_adjusted)
    #     return polyGdal.shape2astext(shape_4326)
    # elseif isa(value, Vector) && length(value) > 0 && isa(value[1], PolyShape)
    #     wkt_vector = String[]
    #     for shape in value
    #         shape_adjusted = polyShape.ajustaCoordenadasInversa(shape, dict_geom["dx"], dict_geom["dy"])
    #         shape_4326 = polyShape.shape_32719to4326(shape_adjusted)
    #         wkt_str = polyGdal.shape2astext(shape_4326)
    #         push!(wkt_vector, wkt_str)
    #     end
    #     return wkt_vector
    else
        return value
    end
end

function createArchitectureDict(variante_norm)
    return OrderedDict(
        "arq_alturaPiso" => 2.55,
        "arq_K" => 1,
        "arq_ancho_crujia_min" => 8,
        "arq_ancho_crujia_max" => 18,
        "arq_tipo_edificio" => "departamento",
        "arq_flag_sombra" => true,
        "arq_flag_vano" => false,
        "arq_vecSupInterior" => [25, 65, 85, 120, 240],
        "arq_vecSupTerraza" => [10, 20, 30, 40, 40],
        "arq_vecSupUtil" => [30, 75, 100, 140, 260],
        "arq_supPorEstacionamiento" => 30,
        "arq_supPorBodega" => 5,
        "arq_supPorBicicleta" => 4,
        "arq_coefSupComunPrimerPiso" => 0.10,
        "arq_coefSupComunPisosSup" => 0.05,
        "arq_coefSupComun" => 0.1,
        "arq_variante_normativa" => variante_norm
    )
end

################################################################################
#                          DATA LOADING SECTION                              #
################################################################################

query_pg = """
SELECT * FROM public.tabla_instancias_optimizacion
WHERE status = 0
ORDER BY id_opti ASC
"""
df_instancias = pg_julia.query(conn_postgres, query_pg)

query_combis = """
MATCH (p:Predio)-[]-(c:Combi)
RETURN DISTINCT c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query_combis, conn_neo4j)

lista_combi_instancias = unique(df_instancias.id_combi)
cypher_list = "[" * join("\"" .* lista_combi_instancias .* "\"", ", ") * "]"

println("Loading geometries from Neo4j...")
query_geom = """
MATCH (c:Combi)-[:CONTIENE_CALLES]->(cc:Calle_Combi)
WHERE c.id_combi IN $cypher_list
RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii,
        c.geom_combi AS geom_wkt, c.num_predios AS num_predios,
        c.calles_contexto_wkt AS calles_contexto_wkt,
        cc.id_calle_combi AS id_calle_combi, cc.geom_wkt AS calles_combi_wkt
ORDER BY id_combi, id_calle_combi
"""
df_combined = neo4j_julia.cypher_to_dataframe(query_geom, conn_neo4j)

################################################################################
#                      MAIN OPTIMIZATION PROCESSING LOOP                     #
################################################################################

const PRIMARY_KEY = "id_opti"
const TABLE_NAME = "tabla_resultados_optimizacion"
const PRIORITY_KEYS = ["id_opti", "id_combi", "flag_sombra", "arq_variante_normativa", "arq_tipo_edificio"]

let flag_create_table = false

    # Check if results table already exists
    table_check_query = """
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = '$TABLE_NAME'
    """
    existing_table = pg_julia.query(conn_postgres, table_check_query)
    if isempty(existing_table)
        flag_create_table = true
        println("Table '$TABLE_NAME' already exists, skipping creation.")
    end

    combi_aux = ""
    dict_geom = nothing

    for row in eachrow(df_instancias)
        id_combi = row.id_combi

        df_combis_row = filter(r -> r.id_combi == id_combi, df_combis)
        vec_predios = parse.(Int, split(strip(df_combis_row[1, "list_predios"], ['(', ')']), ';'))

        if id_combi != combi_aux
            println("\nProcessing Combi ID: $id_combi\n")
            df_combined_row = filter(r -> r.id_combi == id_combi, df_combined)
            dict_geom = obtiene_geometrias_combi(df_combined_row)
            combi_aux = id_combi
        end

        println("Processing ID Opti: $(row.id_opti)")

        dict_arquitectura = createArchitectureDict(row.variante_norm)
        dict_requerimientos = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["arq_variante_normativa"], conn_neo4j)

        dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos, row.id_opti, row.id_combi)

        dict_all = OrderedDict{String,Any}()
        dicts = [dict_resultados, dict_proyecto_vs_normativa, dict_arquitectura]

        for dict in dicts
            for (key, value) in dict
                dict_all[key] = processValue(value, dict_geom)
            end
        end

        dict_all = OrderedDict(sort(collect(dict_all), by=x -> (findfirst(==(x[1]), PRIORITY_KEYS) === nothing ? 1000 : findfirst(==(x[1]), PRIORITY_KEYS), x[1])))

        vecColumnNames, vecColumnTypes = dict2tablevec(dict_all, PRIMARY_KEY)

        if flag_create_table
            pg_julia.createTable(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnTypes, PRIMARY_KEY)
            flag_create_table = false
        end

        vecColumnValue = Vector{Any}(undef, length(vecColumnNames))
        for (idx, col_name) in enumerate(vecColumnNames)
            vecColumnValue[idx] = haskey(dict_all, col_name) ? dict_all[col_name] : nothing
        end

        pg_julia.insertRow!(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnValue, Symbol(PRIMARY_KEY))

        update_query = """
        UPDATE public.tabla_instancias_optimizacion
        SET status = 1
        WHERE id_opti = $(row.id_opti)
        """
        pg_julia.query(conn_postgres, update_query)

        println("Completed optimization for ID Opti: $(row.id_opti)\n")
    end

    println("All optimizations completed successfully!")
end