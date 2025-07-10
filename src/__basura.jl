using LandValue, DotEnv

my_env = DotEnv.config("secrets.env")

conn_aws = aws_julia.connection(my_env["AWS_ACCESS_KEY"], my_env["AWS_SECRET_KEY"], my_env["AWS_REGION"])
instance_info = aws_julia.find_instance_by_name("Neo4j-EC2_JLV", conn_aws)

key_pair   = "neo4j-key-pair.pem"
ec2_user   = "ec2-user"
public_dns = instance_info["dnsName"]

folder = "/usr/bin/cypher-shell"
neo4j_host = "bolt://localhost:7687"
neo4j_user = "neo4j"
neo4j_password = "x67y1332"

conn_neo4j_jlv = neo4j_julia.connection(neo4j_host, neo4j_user, neo4j_password, folder, key_pair, ec2_user, public_dns)

query = """
MATCH (p:Predio {codigo_predial:'151600045900036'})
MATCH (p)-[:PERTENECE_A|PERTENECE_A_USO]->(z)
OPTIONAL MATCH (z)-[:TIENE_VARIANTE_NORMATIVA]->(vn)
OPTIONAL MATCH (vn)-[:TIENE_REQ_NORMATIVO]->(r:Requerimiento_Normativo)
OPTIONAL MATCH (r)-[:TIENE_REQ_CONDICIONAL]->(rc:Requerimiento_Condicional)
WITH
  vn, r, collect(rc) AS condiciones
WITH
  vn, r, CASE WHEN condiciones = [] THEN [null] ELSE condiciones END AS condiciones
UNWIND condiciones AS cond
RETURN
  vn.variante_norm_id        AS variante_norm_id,
  vn.nombre                  AS nombre_variante,
  r.requerimiento_norm_id    AS requerimiento_norm_id,
  r.nombre_requerimiento     AS nombre_requerimiento,
  r.valor                    AS valor,
  r.unidad                   AS unidad,
  r.tipo_restriccion         AS tipo_restriccion,
  cond.requerimiento_cond_id AS requerimiento_cond_id,
  cond.unidad                AS unidad_condicional,
  cond.parametro_formula     AS parametro_formula,
  cond.formula               AS formula,
  cond.nombre_requerimiento  AS nombre_req_condicional;
"""

df = neo4j_julia.cypher_to_dataframe(query, conn_neo4j_jlv)

#  "variante_norm_id"
#  "nombre_variante"
#  "requerimiento_norm_id"
#  "nombre_requerimiento"
#  "valor"
#  "unidad"
#  "tipo_restriccion"
#  "requerimiento_cond_id"
#  "unidad_condicional"
#  "parametro_formula"
#  "formula"
#  "nombre_req_condicional"

df[!,["nombre_variante","nombre_requerimiento","valor","tipo_restriccion","parametro_formula","formula"]]

df1 = df[df[!,"nombre_requerimiento"] .== "distanciamiento", ["nombre_variante","nombre_requerimiento","valor","tipo_restriccion","parametro_formula","formula"]]

df2 = df1[1,"formula"]
n_pisos = 5
expr = Meta.parse(df2)
result = eval(expr)

a=1