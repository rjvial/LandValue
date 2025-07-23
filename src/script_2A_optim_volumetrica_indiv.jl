using LandValue, DotEnv, LinearAlgebra


# tipoOptimizacion = "volumetrica"

my_env = DotEnv.config("secrets.env")
datos_LandValue = ["landengines_dev", my_env["USER_AWS"], my_env["PW_AWS"], my_env["HOST_AWS"]]
datos_mygis_db = ["gis_data", my_env["USER_AWS"], my_env["PW_AWS"], my_env["HOST_AWS"]]

conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])
instance_info = aws_julia.find_instance_by_name("Neo4j-EC2", conn_aws)

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
public_dns = instance_info["dnsName"]

folder = "/usr/bin/cypher-shell"
neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"

conn_neo4j = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

id_ = 0


# WHERE c.id_combi = '13132011001009_2'
query = """
MATCH (p:Predio)-[]-(c:Combi)
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY manzent, id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)


# Problemas con: 6, 9, 12, 13, 21
codigo_predial = parse.(Int, split(strip(df_combis[2,"list_predios"], ['(', ')']), ';')) #18 ok

# temp_opt, alturaPiso, xopt, vec_datos, superficieTerreno, superficieTerrenoBruta, status_optim = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db, []);

