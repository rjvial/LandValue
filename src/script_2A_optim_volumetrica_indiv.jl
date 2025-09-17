using LandValue, DotEnv, LinearAlgebra, OrderedCollections

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
public_dns = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)["dnsName"]
folder = "/usr/bin/cypher-shell"
neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"
conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

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

function dict2tablevec(dicts, primaryKeyStr::String="id")
    if isa(dicts, AbstractDict)
        dicts = [dicts]
    elseif isa(dicts, Vector) && all(x -> isa(x, AbstractDict), dicts)
        # dicts is already a vector of dictionaries
    else
        throw(ArgumentError("Input must be a dictionary or vector of dictionaries"))
    end

    if isempty(dicts)
        throw(ArgumentError("Dictionary vector cannot be empty"))
    end

    all_keys = Set{String}()
    type_map = Dict{String, Type}()
    column_conflicts = Dict{String, Vector{Tuple{Int, Type}}}()

    for (dict_idx, dict) in enumerate(dicts)
        for (key, value) in dict
            push!(all_keys, key)
            value_type = typeof(value)

            if haskey(type_map, key)
                current_type = type_map[key]
                if current_type != value_type
                    if !haskey(column_conflicts, key)
                        column_conflicts[key] = [(1, current_type)]
                    end
                    push!(column_conflicts[key], (dict_idx, value_type))
                end
            else
                type_map[key] = value_type
            end
        end
    end

    if !isempty(column_conflicts)
        @warn "Column conflicts detected - using first occurrence in dictionary order:" column_conflicts
        for (col, conflicts) in column_conflicts
            @warn "Column '$col' conflicts: $(conflicts) - keeping type $(type_map[col]) from first dictionary"
        end
    end

    vecColumnNames = collect(all_keys)
    if !(primaryKeyStr in vecColumnNames)
        push!(vecColumnNames, primaryKeyStr)
        type_map[primaryKeyStr] = Int64
    end

    function sort_columns_with_prefixes(columns)
        unprefixed = String[]
        proyecto_prefixed = String[]
        norm_prefixed = String[]
        arq_prefixed = String[]

        for col in columns
            if startswith(col, "proyecto_")
                push!(proyecto_prefixed, col)
            elseif startswith(col, "norm_")
                push!(norm_prefixed, col)
            elseif startswith(col, "arq_")
                push!(arq_prefixed, col)
            else
                push!(unprefixed, col)
            end
        end

        return vcat(sort(unprefixed), sort(proyecto_prefixed), sort(norm_prefixed), sort(arq_prefixed))
    end

    vecColumnNames = sort_columns_with_prefixes(vecColumnNames)
    vecColumnTypes = [juliaTypeToPgType(type_map[col]) for col in vecColumnNames]

    return vecColumnNames, vecColumnTypes
end


query_pg = """
SELECT * FROM public.tabla_instancias_optimizacion
ORDER BY id_instancia ASC 
"""
df_instancias = pg_julia.query(conn_postgres, query_pg)

query = """
    MATCH (p:Predio)-[]-(c:Combi)
    RETURN DISTINCT  c.id_combi AS id_combi, c.predios AS list_predios
    ORDER BY id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

lista_combi_instancias = unique(df_instancias.id_combi)
cypher_list = "[" * join("\"" .* lista_combi_instancias .* "\"", ", ") * "]"

display("Obtiene las geometrias de los predios y calles desde Neo4j")
query = """
    MATCH (c:Combi)-[:CONTIENE_CALLES]->(cc:Calle_Combi)
    WHERE c.id_combi IN $cypher_list
    RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii, 
            c.geom_combi AS geom_wkt, c.num_predios AS num_predios, 
            c.calles_contexto_wkt AS calles_contexto_wkt,
            cc.id_calle_combi AS id_calle_combi, cc.geom_wkt AS calles_combi_wkt
    ORDER BY id_combi, id_calle_combi
"""
df_combined = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

########### partialPolyOffset No esta funcionando bien: prbar con 13132011001009_24
# row = df_instancias[df_instancias.id_combi .== "13132011002005_19",:]
flag_create_table = false
for row in eachrow(df_instancias)
    id_combi = row.id_combi

    df_combis_row = filter(r -> r.id_combi == id_combi, df_combis)
    vec_predios = parse.(Int, split(strip(df_combis_row[1,"list_predios"], ['(', ')']), ';')) #18 ok

    df_combined_row = filter(r -> r.id_combi == id_combi, df_combined)

    # try
        dict_geom = obtiene_geometrias_combi(df_combined_row)

        list_variantes = row.list_variantes
        vec_variantes = sort(split(row.list_variantes, ","))

        num_variante = row.num_variantes
        for i = 1:num_variante
            println("ID Combi: ", row.id_combi, " - Variante: ", vec_variantes[i])
            dict_arquitectura = OrderedDict(
                "arq_alturaPiso" => 2.55,
                "arq_K" => 1,
                "arq_ancho_crujia_min" => 8,
                "arq_ancho_crujia_max" => 18,
                "arq_tipo_edificio" => "departamento",
                "arq_flag_sombra" => true, #false, #
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
                "arq_variante_normativa" => vec_variantes[i]
            )

            dict_requerimientos = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["arq_variante_normativa"], conn_neo4j);

            dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos, row.id_instancia, row.id_combi)
            # show(IOContext(stdout, :limit => false), MIME("text/plain"), dict_proyecto_vs_normativa)
            # show(IOContext(stdout, :limit => false), MIME("text/plain"), dict_resultados)

            println("")
            println("")
            
            # primaryKeyStr = "id_opti"
            # tableNameStr = "prueba"

            # dicts = [dict_resultados, dict_requerimientos, dict_proyecto_vs_normativa, dict_arquitectura]

            # dict_all = OrderedDict{String, Any}()
            # for dict in dicts
            #     for (key, value) in dict
            #         if typeof(value) == Bool
            #             dict_all[key] = value ? 1 : 0
            #         else
            #             dict_all[key] = value
            #         end
            #     end
            # end

            # if flag_create_table
            #     vecColumnNames, vecColumnTypes = dict2tablevec(dict_all, primaryKeyStr)
            #     pg_julia.createTable(conn_postgres, tableNameStr, vecColumnNames, vecColumnTypes, primaryKeyStr)

            #     flag_create_table = false
            # end

            
            # id_opti_index = findfirst(x -> x == "id_opti", vecColumnNames_)
            # vecColumnValue_[id_opti_index] = row.id_instancia * 10 + i
            
            # pg_julia.insertRow!(conn_postgres, tableNameStr, vecColumnNames, vecColumnValue, :id_opti)


            fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["arq_alturaPiso"], dict_geom["ps_combi"], dict_resultados)
        end
    
    # catch
    #     println("")
    #     println("")
    #     println("No se pudo procesar la combi ", id_combi)
    #     println("")
    #     println("")
    # end
end

# id_combi = "13132011001012_31" #"13132011001009_40" "13132011001012_82" "13132011001014_4"
# "13132011001009_24"

