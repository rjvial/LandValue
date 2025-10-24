################################################################################
#                    SCRIPT 2A - VOLUMETRIC OPTIMIZATION                     #
################################################################################

using LandValue, DotEnv, LinearAlgebra, OrderedCollections, JSON

################################################################################
#                        DATABASE CONNECTION SETUP                           #
################################################################################

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

neo4j_host = "bolt://localhost:7687"
# neo4j_host = "bolt://localhost:7688"
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


function update_optimization_status(conn_postgres, id_opti, status)
    update_query = """
    UPDATE public.tabla_instancias_optimizacion
    SET status = $status
    WHERE id_opti = $id_opti
    """
    pg_julia.query(conn_postgres, update_query)
end

function handle_optimization_error(conn_postgres, id_opti, error_msg, error)
    println("$error_msg for ID $id_opti: $error")
    update_optimization_status(conn_postgres, id_opti, -1)
end

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
        "arq_coefSupComunPisosSup" => 0.12,
        "arq_coefSupComun" => 0.18,
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
MATCH (p:Predio)-[:CONFORMA_COMBI]->(c:Combi)
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

println("Loading tipo deptos from athena...")
query = """
SELECT * FROM portal_tipo_deptos
WHERE comuna = 'vitacura'
"""
DB_NAME = "iceberg_db"
athena_bucket = "landengines-data"
athena_output = "query-results"
athena_catalog_name = "AwsDataCatalog"
df_tipo_deptos = aws_julia.query_to_dataframe(query, DB_NAME, athena_bucket, athena_output, athena_catalog_name, conn_aws)


################################################################################
#                      MAIN OPTIMIZATION PROCESSING LOOP                     #
################################################################################

const PRIMARY_KEY = "id_opti"
const TABLE_NAME = "tabla_resultados_optimizacion"
const PRIORITY_KEYS = ["id_opti", "id_combi", "flag_sombra", "arq_variante_normativa", "arq_tipo_edificio"]

flag_create_table = false # let flag_create_table = false

    # Check if results table already exists
    table_check_query = """
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = '$TABLE_NAME'
    """
    existing_table = pg_julia.query(conn_postgres, table_check_query)
    if isempty(existing_table)
        flag_create_table = true
        println("Table '$TABLE_NAME' does not exist, will create on first result")
    else
        println("Table '$TABLE_NAME' already exists")
    end

    combi_aux = ""
    dict_geom = nothing

    for row in eachrow(df_instancias)
        id_combi = row.id_combi
        id_opti = row.id_opti

        df_combis_row = filter(r -> r.id_combi == id_combi, df_combis)
        vec_predios = parse.(Int, split(strip(df_combis_row[1, "list_predios"], ['(', ')']), ';'))

        # Process geometry once per combi
        if id_combi != combi_aux
            println("\nProcessing Combi ID: $id_combi\n")
            df_combined_row = filter(r -> r.id_combi == id_combi, df_combined)

            # if isempty(df_combined_row)
            #     handle_optimization_error(conn_postgres, id_opti, "No geometries found", "")
            #     continue
            # end

            # try
                dict_geom = obtiene_geometrias_combi(df_combined_row)
            # catch e
            #     println("Geometry processing error for Combi ID $(id_combi): $(e). Skipping this optimization.")
            #     handle_optimization_error(conn_postgres, id_opti, "Geometry processing error", string(e))
            #     continue
            # end

            combi_aux = id_combi
        end

        println("Processing ID Opti: $(id_opti)")


        dict_arquitectura = createArchitectureDict(row.variante_norm)
        dict_normativa_raw, id_zona_edificacion = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["arq_variante_normativa"], conn_neo4j)

        # id_zona_edificacion = "15160_e_aa1"
        df_tipo_deptos_filtered = filter(r -> r.id_zona_edificacion == id_zona_edificacion, df_tipo_deptos)
        dict_arquitectura["arq_vecSupUtil"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_util_tipos_comuna"]))
        dict_arquitectura["arq_vecSupInterior"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_interior_tipos_comuna"]))
        dict_arquitectura["arq_vecSupTerraza"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"sup_terraza_tipos_comuna"]))
        dict_arquitectura["arq_vecDormitorios"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"n_dorm_tipos_comuna"]))
        dict_arquitectura["arq_vecBanos"] = Float64.(JSON.parse(df_tipo_deptos_filtered[1,"n_banos_tipos_comuna"]))

        # try
            dict_proyecto, dict_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_normativa_raw, id_opti, id_combi)
            # show(IOContext(stdout, :limit => false), MIME("text/plain"), dict_resultados)


            ####################################
            ####################################
            vec_sup_deptos = dict_arquitectura["arq_vecSupInterior"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
            vec_num_deptos = dict_proyecto["proyecto_vec_num_deptos_primerPiso"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
            vec_sup_terraza = dict_arquitectura["arq_vecSupTerraza"][dict_proyecto["proyecto_vec_num_deptos_primerPiso"].>=1]
            ps_planta = dict_proyecto["proyecto_vec_ps_opt"][1]

            results_ns = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos,
                             layout=:ns,
                             ancho_pasillo=1.5,
                             vec_sup_terraza=vec_sup_terraza,
                             con_escala = false,
                             min_dimension_escala=0*4.0,
                             area_escala=1*20.0,
                             min_largo_pasillo=5.0,
                             pasillo_centrado=true)
            fig_ns, ax_ns, ax_mat_ns = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
            polyPlot.plotPolyshape2D(results_ns["ps_pasillo"], "#505050", 0.9, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
            polyPlot.plotPolyshape2D(results_ns["ps_escala"], "#303030", 0.9, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
            for apt_poly in results_ns["vec_polyshapes_all"]
                polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
            end
            for terrace in results_ns["vec_terrazas_all"]
                if polyShape.polyArea(terrace) > 0.0
                    polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_ns, ax=ax_ns, ax_mat=ax_mat_ns)
                end
            end
            ax_ns.set_aspect("equal")

            results_oe = opti_floor_plan(ps_planta, vec_sup_deptos, vec_num_deptos,
                             layout=:oe,
                             ancho_pasillo=1.5,
                             vec_sup_terraza=vec_sup_terraza,
                             con_escala = true,
                             min_dimension_escala=0*4.0,
                             area_escala=1*20.0,
                             min_largo_pasillo=5.0,
                             pasillo_centrado=false)
            fig_oe, ax_oe, ax_mat_oe = polyPlot.plotPolyshape2D(ps_planta, "green", 0.2)
            polyPlot.plotPolyshape2D(results_oe["ps_pasillo"], "#505050", 0.9, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
            polyPlot.plotPolyshape2D(results_oe["ps_escala"], "#303030", 0.9, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
            for apt_poly in results_oe["vec_polyshapes_all"]
                polyPlot.plotPolyshape2D(apt_poly, "red", 0.3, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
            end
            for terrace in results_oe["vec_terrazas_all"]
                if polyShape.polyArea(terrace) > 0.0
                    polyPlot.plotPolyshape2D(terrace, "blue", 0.4, fig=fig_oe, ax=ax_oe, ax_mat=ax_mat_oe)
                end
            end
            ####################################
            ####################################



            dict_json = OrderedDict()
            dict_json["n_predios"] = dict_geom["n_predios"]
            dict_json["sup_terreno_sii"] = dict_geom["sup_terreno_sii"]
            dict_json["sup_terreno_bruto"] = dict_geom["sup_terreno_bruto"]
            dict_json["json_edificio_opt"] = polyShape.building2json(dict_proyecto["proyecto_vec_ps_opt"], dict_proyecto["proyecto_vec_np_opt"], dict_arquitectura["arq_alturaPiso"])
            dict_json["json_subte_opt"] = polyShape.building2json(dict_proyecto["proyecto_vec_ps_subte"], dict_proyecto["proyecto_vec_np_subte"], dict_arquitectura["arq_alturaPiso"])
            dict_json["json_Volteor"] = polyShape.polyShapeLayers2json(dict_proyecto["proyecto_vec_psVolteor"], dict_proyecto["proyecto_vec_altVolteor"])
            dict_json["json_sombraEdif_p"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraEdif_p"])
            dict_json["json_sombraEdif_o"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraEdif_o"])
            dict_json["json_sombraEdif_s"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraEdif_s"])
            dict_json["json_sombraVolTeorico_p"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraVolTeorico_p"])
            dict_json["json_sombraVolTeorico_o"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraVolTeorico_o"])
            dict_json["json_sombraVolTeorico_s"] = polyShape.polyShape2json(dict_proyecto["proyecto_ps_sombraVolTeorico_s"])
            dict_json["json_combi"] = polyShape.polyShape2json(dict_geom["ps_combi"])
            dict_json["json_bruto"] = polyShape.polyShape2json(dict_geom["ps_bruto"])
            dict_json["json_calles"] = polyShape.polyShape2json(dict_geom["ps_calles"])
            dict_json["json_calles_contexto"] = polyShape.polyShape2json(dict_geom["ps_calles_contexto"])

            delete!(dict_normativa, "norm_coeficiente_de_ocupacion_de_suelo")
            delete!(dict_normativa, "norm_superficice_util_max_depto")
            delete!(dict_normativa, "norm_coeficiente_de_constructibilidad")
            delete!(dict_normativa, "norm_superficice_min_patio_x_depto")

            dict_all = OrderedDict{String,Any}()
            dicts = [dict_normativa, dict_proyecto, dict_arquitectura, dict_json]

            for dict in dicts
                for (key, value) in dict
                    dict_all[key] = processValue(value, dict_geom)
                end
            end

            # vecColumnNames, vecColumnTypes = dict2tablevec(dict_all, PRIMARY_KEY)

            # if flag_create_table
            #     pg_julia.createTable(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnTypes, PRIMARY_KEY)
            #     flag_create_table = false
            # end

            # vecColumnValue = Vector{Any}(undef, length(vecColumnNames))
            # for (idx, col_name) in enumerate(vecColumnNames)
            #     vecColumnValue[idx] = haskey(dict_all, col_name) ? dict_all[col_name] : nothing
            # end

            # pg_julia.insertRow!(conn_postgres, TABLE_NAME, vecColumnNames, vecColumnValue, Symbol(PRIMARY_KEY))

            # update_optimization_status(conn_postgres, id_opti, 1)

            # fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["arq_alturaPiso"], dict_geom["ps_combi"], dict_all)

            println("Completed optimization for ID Opti: $(id_opti)\n")

        # catch e
        #     handle_optimization_error(conn_postgres, id_opti, "Optimization failed", e)
        #     continue
        # end

    end

    println("All optimizations completed successfully!")
# end