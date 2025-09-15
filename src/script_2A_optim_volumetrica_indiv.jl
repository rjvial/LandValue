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

query_pg = """
SELECT * FROM public.tabla_instancias_optimizacion
ORDER BY id_instancia ASC 
"""
df_instancias = pg_julia.query(conn_postgres, query_pg)

########### partialPolyOffset No esta funcionando bien: prbar con 13132011001009_24
# row = df_instancias[df_instancias.id_combi .== "13132011001009_24",:]
for row in eachrow(df_instancias)
    id_combi = row.id_combi

    query = """
        MATCH (p:Predio)-[]-(c:Combi)
        WHERE c.id_combi = '$id_combi'
        RETURN DISTINCT  c.id_combi AS id_combi, c.predios AS list_predios
        ORDER BY id_combi
    """
    df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
    
    vec_predios = parse.(Int, split(strip(df_combis[1,"list_predios"], ['(', ')']), ';')) #18 ok

    display("Obtiene desde Neo4j las geometrias de los predios y calles")
    query = """
        MATCH (c:Combi)-[:CONTIENE_CALLES]->(cc:Calle_Combi)
        WHERE c.id_combi = '$id_combi'
        RETURN DISTINCT c.id_combi AS id_combi, c.sup_combi_sii AS sup_terreno_sii, 
                c.geom_combi AS geom_wkt, c.num_predios AS num_predios, 
                c.calles_contexto_wkt AS calles_contexto_wkt,
                cc.id_calle_combi AS id_calle_combi, cc.geom_wkt AS calles_combi_wkt
        ORDER BY id_combi, id_calle_combi
    """
    df_combined = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

    
    try #if !isempty(df_combined)
        dict_geom = obtiene_geometrias_combi(df_combined)

        list_variantes = row.list_variantes
        vec_variantes = sort(split(row.list_variantes, ","))

        num_variante = row.num_variantes
        for i = 1:num_variante
            println("ID Combi: ", row.id_combi, " - Variante: ", vec_variantes[i])
            dict_arquitectura = OrderedDict(
                "alturaPiso" => 2.55,
                "K" => 1,
                "ancho_crujia_min" => 8,
                "ancho_crujia_max" => 18,
                "tipo_edificio" => "departamento",
                "flag_sombra" => true, #false, # 
                "flag_vano" => false,
                "vecSupInterior" => [25, 65, 85, 120, 240],
                "vecSupTerraza" => [10, 20, 30, 40, 40],
                "vecSupUtil" => [30, 75, 100, 140, 260],
                "supPorEstacionamiento" => 30,
                "supPorBodega" => 5,
                "supPorBicicleta" => 4,
                "coefSupComunPrimerPiso" => 0.10,
                "coefSupComunPisosSup" => 0.05,
                "coefSupComun" => 0.1,
                "variante_normativa" => vec_variantes[i]
            )

            dict_requerimientos = obtiene_requerimientos_normativos(vec_predios[1], dict_arquitectura["variante_normativa"], conn_neo4j);

            dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
            display(dict_proyecto_vs_normativa);

            println("")
            println("")

            fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["alturaPiso"], dict_geom["ps_combi"], dict_resultados)
        end
    
    catch
        println("")
        println("")
        println("No se pudo procesar la combi ", id_combi)
        println("")
        println("")
    end
end

# id_combi = "13132011001012_31" #"13132011001009_40" "13132011001012_82" "13132011001014_4"
# "13132011001009_24"

