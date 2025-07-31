using LandValue, DotEnv, LinearAlgebra, OrderedCollections

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


sup_combi_sii_min = 800;    sup_combi_sii_max = 4000
length_min_combi = 38;      length_max_combi = 120
width_min_combi = 20;       width_max_combi = 65
length_to_width_min = 1;    length_to_width_max = 5.0
rectangularity_min = 0.95;  rectangularity_max = 1
convexity_min = 0.95;       convexity_max = 1
num_predios_min = 1;        num_predios_max = 12


query = """
MATCH (p:Predio)-[]-(c:Combi)
WHERE c.length >= $length_min_combi AND c.length <= $length_max_combi
AND c.width >= $width_min_combi AND c.width <= $width_max_combi
AND c.length_to_width >= $length_to_width_min AND c.length_to_width <= $length_to_width_max
AND c.rectangularity >= $rectangularity_min AND c.rectangularity <= $rectangularity_max
AND c.convexity >= $convexity_min AND c.convexity <= $convexity_max
AND c.sup_combi_sii >= $sup_combi_sii_min AND c.sup_combi_sii <= $sup_combi_sii_max
AND c.num_predios >= $num_predios_min AND c.num_predios <= $num_predios_max
RETURN DISTINCT  c.manzent AS manzent, c.id_combi AS id_combi, c.predios AS list_predios, 
c.rectangularity AS rectangularity, c.convexity AS convexity, c.length AS length, c.width AS  width
ORDER BY manzent, id_combi
"""
df_combis = neo4j_julia.cypher_to_dataframe(query, conn_neo4j)
codigo_predial = parse.(Int, split(strip(df_combis[103,"list_predios"], ['(', ')']), ';')) #18 ok
# con problemas: 10, 100, 200

dict_geom = obtiene_geometrias_codigo_predial(codigo_predial, conn_neo4j)


println("###########################################")
println("Caso base")
println("###########################################")

# Caso base
dict_arquitectura = OrderedDict(
    "alturaPiso" => 2.55,
    "K" => 1,
    "ancho_crujia_min" => 8,
    "ancho_crujia_max" => 18,
    "tipo_edificio" => "departamento",
    "flag_sombra" => true,
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
    "variante_normativa" => "base" #"dfl_2" #"vivienda_economica" #  
)
dict_requerimientos = obtiene_requerimientos_normativos(codigo_predial, dict_arquitectura["variante_normativa"], conn_neo4j);
if length(dict_requerimientos) > 5
    dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    display(dict_proyecto_vs_normativa);
end


println("###########################################")
println("Caso dfl_2")
println("###########################################")

# Caso dfl_2
dict_arquitectura = OrderedDict(
    "alturaPiso" => 2.55,
    "K" => 1,
    "ancho_crujia_min" => 8,
    "ancho_crujia_max" => 18,
    "tipo_edificio" => "departamento",
    "flag_sombra" => true,
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
    "variante_normativa" => "dfl_2" #"vivienda_economica" # "base" # 
)
dict_requerimientos = obtiene_requerimientos_normativos(codigo_predial, dict_arquitectura["variante_normativa"], conn_neo4j);
if length(dict_requerimientos) > 5
    dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    display(dict_proyecto_vs_normativa);
end


println("###########################################################")
println("Caso vivienda económica")
println("###########################################################")

# Caso vivienda_economica 
dict_arquitectura = OrderedDict(
    "alturaPiso" => 2.55,
    "K" => 1,
    "ancho_crujia_min" => 8,
    "ancho_crujia_max" => 18,
    "tipo_edificio" => "departamento",
    "flag_sombra" => true,
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
    "variante_normativa" => "vivienda_economica" #"dfl_2" # "base" # 
)
dict_requerimientos = obtiene_requerimientos_normativos(codigo_predial, dict_arquitectura["variante_normativa"], conn_neo4j);
if length(dict_requerimientos) > 5
    dict_resultados, dict_proyecto_vs_normativa = opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    display(dict_proyecto_vs_normativa);
end


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

display(dict_proyecto_vs_normativa)
