using LandValue, Distributed, DotEnv 

my_env = DotEnv.config("secrets.env")
conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])

pg_public_dns = aws_julia.find_instance_by_name("Postgres-EC2", conn_aws)["dnsName"]
conn_postgres = pg_julia.connection("landengines", my_env["PG_AWS_USER"], my_env["PG_AWS_PASSWORD"], pg_public_dns)

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
neo4j_public_dns = aws_julia.find_instance_by_name("Neo4j-EC2-V2", conn_aws)["dnsName"]
folder = "/usr/bin/cypher-shell"
neo4j_host = my_env["NEO4J_URI"]

neo4j_user = my_env["NEO4J_USER"]
neo4j_password = my_env["NEO4J_PASSWORD"]
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
        "id_opti" serial PRIMARY KEY,
        "id_combi" text,
        "variante_norm" text,
        "status" int
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
all_predios_int = [parse(Int64, p) for p in all_predios]

batch_query = """
    MATCH (c:Combi)-[]-(p:Predio)-[:SE_UBICA_EN_ZONA]->(z:Zona_Edificacion)-[:TIENE_REQUERIMIENTO]->(r:Requerimiento_Edificacion)
    WHERE p.codigo_predial IN [$(join(["$p" for p in unique(all_predios)], ","))]
    AND c.length >= $length_min_combi AND c.length <= $length_max_combi
    AND c.width >= $width_min_combi AND c.width <= $width_max_combi
    AND c.length_to_width >= $length_to_width_min AND c.length_to_width <= $length_to_width_max
    AND c.rectangularity >= $rectangularity_min AND c.rectangularity <= $rectangularity_max
    AND c.convexity >= $convexity_min AND c.convexity <= $convexity_max
    AND c.sup_combi_sii >= $sup_combi_sii_min AND c.sup_combi_sii <= $sup_combi_sii_max
    AND c.num_predios >= $num_predios_min AND c.num_predios <= $num_predios_max
    RETURN DISTINCT c.id_combi AS id_combi, r.nombre_variante AS nombre_variante
    ORDER BY id_combi, nombre_variante
    """
df_all_variants = neo4j_julia.cypher_to_dataframe(batch_query, conn_neo4j)

insert_values = []
let cont = 0
    for row in eachrow(df_all_variants)
        cont += 1
        println("Processing Combi ID: ", row.id_combi, ", contador: ", string(cont))
        push!(insert_values, "($(cont), '$(row.id_combi)', '$(row.nombre_variante)', 0)")
    end

    if !isempty(insert_values)
        bulk_insert_sql = """
        INSERT INTO tabla_instancias_optimizacion (id_opti, id_combi, variante_norm, status) 
        VALUES $(join(insert_values, ","))
        """
        pg_julia.query(conn_postgres, bulk_insert_sql)
        println("Inserted $(length(insert_values)) rows in batch")
    end

end
