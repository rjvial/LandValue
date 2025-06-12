using LandValue, DotEnv, LinearAlgebra


tipoOptimizacion = "volumetrica"

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



query = """
MATCH (p:Predio)-[]-(c:Combi)
WHERE p.comuna = 'vitacura' 
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY manzent, id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)


# Problemas con: 200, 300, 400, 600
codigo_predial = parse.(Int, split(strip(df_combis[1,"list_predios"], ['(', ')']), ';'))


temp_opt, alturaPiso, xopt, vec_datos, superficieTerreno, superficieTerrenoBruta, status_optim = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db, []);


display("Obtiene FlagPlotEdif3D")
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
id = 1


ps_predio = vec_datos[1]
vec_psVolteor = vec_datos[2]
vec_altVolteor = vec_datos[3]
ps_publico = vec_datos[4]
ps_calles = vec_datos[5]
ps_base = vec_datos[6]
ps_baseSeparada = vec_datos[7]
ps_primerPiso = vec_datos[8]
ps_calles_intra_buffer = vec_datos[9]
ps_predios_intra_buffer = vec_datos[10]
ps_manzanas_intra_buffer = vec_datos[11]
ps_buffer_predio = vec_datos[12]
dx = vec_datos[13]
dy = vec_datos[14]
ps_areaEdif = vec_datos[15]


fig, ax, ax_mat = polyShape.plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)

