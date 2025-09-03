using LandValue, Distributed, DotEnv 

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
neo4j_public_dns = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)["dnsName"]
folder = "/usr/bin/cypher-shell"
neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"
conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, neo4j_public_dns)


query_check_instancias_optimizacion = """
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'tabla_instancias_optimizacion'
"""
df_check_instancias_optimizacion = pg_julia.query(conn_postgres, query_check_instancias_optimizacion)
if isempty(df_check_instancias_optimizacion) # En caso que no exista la tabla instancias_optimizacion
    query_str = """ 
    CREATE TABLE IF NOT EXISTS public.tabla_instancias_optimizacion
    (
        "id_instancia" serial PRIMARY KEY,
        "id_combi" text,
        "list_predios" text,
        "list_variantes" text,
        "num_variantes" int,
        "status" int
    )
    """
    pg_julia.query(conn_postgres, query_str)
end

query_check_resultados_optimizacion = """
SELECT 1 FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'tabla_resultados_optimizacion'
"""
df_check_resultados_optimizacion = pg_julia.query(conn_postgres, query_check_resultados_optimizacion)

if isempty(df_check_resultados_optimizacion)
    query_str = """ 
    CREATE TABLE IF NOT EXISTS public.tabla_resultados_optimizacion
    (
        "tipo_edificio" text,
        "variante_normativa" text,
        "flag_sombra" text,
        "sup_edificada_snt" float,
        "cabida_sup_deptos" float,
        "cabida_num_deptos" int,
        "cabida_sup_comercio" float,
        "cabida_num_comercio" int,
        "cabida_sup_oficinas" float,
        "cabida_num_oficinas" int,
        "estacionamientos_autos_oficina" int,
        "estacionamientos_autos_vivienda" int,
        "estacionamientos_autos_comercio" int,
        "estacionamientos_autos" int,
        "estacionamientos_visitas" int,
        "estacionamientos_discapacitados" int,
        "estacionamientos_bicicletas" int,
        "descuento_estacionamientos_x_metro" int,
        "descuento_estacionamientos_x_bici_t1" int,
        "descuento_estacionamientos_x_bici_t2" int,
        "descuento_estacionamientos_x_bici" int,
        "aumento_bici_x_descuento_estacionamientos" int,
        "estacionamientos_autos_final" int,
        "estacionamientos_bicicletas_final" int,
        "bodegas" int,
        "dict_edificio_deptos" text,
        
        "vec_ps_opt" text,
        "vec_np_opt" text,
        "vec_ps_subte" text,
        "vec_np_subte" text,
        "vec_psVolteor" text,
        "vec_altVolteor" text,
        "vec_psVolConSombra" text,
        "vec_altVolConSombra" text,
        "ps_sombraEdif_p" text,
        "ps_sombraEdif_o" text,
        "ps_sombraEdif_s" text,
        "ps_sombraVolTeorico_p" text,
        "ps_sombraVolTeorico_o" text,
        "ps_sombraVolTeorico_s" text
    )
    """
    pg_julia.query(conn_postgres, query_str)

end



sup_combi_sii_min = 800;    sup_combi_sii_max = 4000
length_min_combi = 38;      length_max_combi = 120
width_min_combi = 20;       width_max_combi = 65
length_to_width_min = 1;    length_to_width_max = 5.0
rectangularity_min = 0.95;  rectangularity_max = 1
convexity_min = 0.95;       convexity_max = 1
num_predios_min = 1;        num_predios_max = 12
query = """
MATCH (c:Combi)
WHERE c.length >= $length_min_combi AND c.length <= $length_max_combi
    AND c.width >= $width_min_combi AND c.width <= $width_max_combi
    AND c.length_to_width >= $length_to_width_min AND c.length_to_width <= $length_to_width_max
    AND c.rectangularity >= $rectangularity_min AND c.rectangularity <= $rectangularity_max
    AND c.convexity >= $convexity_min AND c.convexity <= $convexity_max
    AND c.sup_combi_sii >= $sup_combi_sii_min AND c.sup_combi_sii <= $sup_combi_sii_max
    AND c.num_predios >= $num_predios_min AND c.num_predios <= $num_predios_max
RETURN DISTINCT c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

all_predios = unique([split(strip(row.list_predios, ['(', ')']), ";")[1] for row in eachrow(df_combis)])
println("All predios: ", all_predios[1:min(5, length(all_predios))])

all_predios_int = [parse(Int64, p) for p in all_predios]
println("All predios as int: ", all_predios_int[1:min(5, length(all_predios_int))])

batch_query = """
    MATCH (p:Predio)-[:SE_UBICA_EN_ZONA]->(z:Zona_Edificacion)-[:TIENE_REQUERIMIENTO]->(r:Requerimiento_Edificacion)
    WHERE p.codigo_predial IN [$(join(["\"$p\"" for p in unique(all_predios)], ","))]
    RETURN DISTINCT p.codigo_predial AS codigo_predial, r.nombre_variante AS nombre_variante
    """
df_all_variants = neo4j_julia.cypher_to_dataframe(batch_query, conn_neo4j)

insert_values = []

for row in eachrow(df_combis)
    println("Processing Combi ID: ", row.id_combi)
    id_combi = row.id_combi
    list_predios = row.list_predios
    vec_predios = split(strip(list_predios, ['(', ')']), ";")

    predio_variants = filter(r -> r.codigo_predial == parse(Int64, vec_predios[1]), df_all_variants)
    if isempty(predio_variants)
        list_variantes = ""
        num_variantes = 0
    else
        list_variantes = join(predio_variants.nombre_variante, ",")
        num_variantes = size(predio_variants, 1)
    end
    status = num_variantes
    
    escaped_list_predios = replace(list_predios, "'" => "''")
    escaped_list_variantes = replace(list_variantes, "'" => "''")
    escaped_id_combi = replace(string(id_combi), "'" => "''")
    
    push!(insert_values, "('$(escaped_id_combi)', '$(escaped_list_predios)', '$(escaped_list_variantes)', $(num_variantes), $(status))")
end

if !isempty(insert_values)
    bulk_insert_sql = """
    INSERT INTO tabla_instancias_optimizacion (id_combi, list_predios, list_variantes, num_variantes, status) 
    VALUES $(join(insert_values, ","))
    """
    pg_julia.query(conn_postgres, bulk_insert_sql)
    println("Inserted $(length(insert_values)) rows in batch")
end


