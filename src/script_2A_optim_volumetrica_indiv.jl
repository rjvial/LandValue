using LandValue, DotEnv, LinearAlgebra


my_env = DotEnv.config("secrets.env")


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
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios
ORDER BY manzent, id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)

# Problemas con: 
codigo_predial = parse.(Int, split(strip(df_combis[2,"list_predios"], ['(', ')']), ';')) #18 ok

alturaPiso = 2.55
supInterior = [25, 65, 85, 120, 240]
supTerraza = [10, 20, 30, 40, 40]
supDeptoUtil = supInterior .+ 0.5 * supTerraza

K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = false; tipo_edificio = "oficina"
# K = 3; ancho_crujia_min = 0; ancho_crujia_max = 0; flag_sombra = true; tipo_edificio = "oficina"
# K = 1; ancho_crujia_min = 8; ancho_crujia_max = 18; flag_sombra = false; tipo_edificio = "departamento"
# K = 1; ancho_crujia_min = 8; ancho_crujia_max = 18; flag_sombra = true; tipo_edificio = "departamento"
dict_arquitectura = Dict(
    "alturaPiso" => alturaPiso,
    "K" => K,
    "ancho_crujia_min" => ancho_crujia_min,
    "ancho_crujia_max" => ancho_crujia_max,
    "tipo_edificio" => tipo_edificio,
    "flag_sombra" => flag_sombra,
    "supInterior" => supInterior,
    "supTerraza" => supTerraza,
    "supDeptoUtil" => supDeptoUtil,
    "supPorEstacionamiento" => 30,
    "supPorBodega" => 5,
    "supPorBicicleta" => 4,
    "coefSupComunPrimerPiso" => 0.4,
    "coefSupComunPisosSup" => 0.1,
    "variante_normativa" => "dfl_2"
)


dict_resultados, dict_arquitectura, dict_geom = funcionPrincipal(conn_neo4j, codigo_predial, dict_arquitectura);


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

fig, ax, ax_mat = plotBaseEdificio3D(fpe, dict_arquitectura["alturaPiso"], dict_geom["ps_predio"], dict_resultados["vec_psVolteor"], dict_resultados["vec_altVolteor"], dict_resultados["vec_psVolConSombra"], dict_resultados["vec_altVolConSombra"], dict_geom["ps_publico"], dict_geom["ps_calles"], dict_resultados["vec_ps_opt"], dict_resultados["vec_np_opt"], dict_resultados["vec_ps_subte"], dict_resultados["vec_np_subte"], dict_resultados["tipo_edificio"])

