using LandValue, Distributed, DotEnv

#[151600217300088, 151600217300089, 151600217300090, 151600217300091, 151600217300092, 151600217300093, 151600217300094, 151600217300095, 151600217300096, 151600217300097, 151600217300098]
#[151600217300071, 151600217300072, 151600217300073, 151600217300074, 151600217300075, 151600217300087, 151600217300088, 151600217300089, 151600217300090, 151600217300091, 151600217300092]
#[151600189900002, 151600189900003, 151600189900004, 151600189900005, 151600189900006, 151600189900007, 151600189900018, 151600189900019, 151600189900022, 151600189900023, 151600189900024]
#[151600189900005, 151600189900006, 151600189900007, 151600189900008, 151600189900017, 151600189900018, 151600189900019, 151600189900020, 151600189900021, 151600189900022, 151600189900023]

#[151600231900001, 151600231900002, 151600231900003, 151600231900004, 151600231900005, 151600231900008]

codigo_predial = [151600340500127, 151600340500128]


tipoOptimizacion = "volumetrica"

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

temp_opt, alturaPiso, xopt, vec_datos, superficieTerreno, superficieTerrenoBruta, status_optim = funcionPrincipal(tipoOptimizacion, codigo_predial, 0, datos_LandValue, datos_mygis_db, []);


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


fig, ax, ax_mat = plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, vec_psVolteor, vec_altVolteor, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)


# # datos contiene la información necesaria para correr la Evaluación Económica
# datos = [xopt[1]*alturaPiso, ps_base, superficieTerreno, superficieTerrenoBruta, xopt, ps_areaEdif];


# UPDATE tabla_combinacion_predios
# SET status = 0 

# UPDATE tabla_combinacion_predios
# SET status = 0 
# WHERE combi_predios_str = '[151600135700009, 151600135700003, 151600135700004, 151600135700005, 151600135700016, 151600135700017, 151600135700018, 151600135700019, 151600135700020]';

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines  --table="tabla_resultados_cabidas" | psql -d landengines_dev -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres
#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "tabla_resultados_cabidas" | psql -d landengines_local -h localhost -U postgres
#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "tabla_costosunitarios_default" -t "tabla_flagplot_default" -t "tabla_normativa_default" -t "tabla_normativa_default" | psql -d landengines_local -h localhost -U postgres

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d gis_data -t "anteproyectos_vitacura" -t "areas_verde_vitacura" -t "datos_cbrs_vitacura" -t "datos_manzanas_vitacura_2017" -t "datos_manzanas_vitacura_ampliado_2017" -t "datos_predios_vitacura" -t "datos_roles_vitacura" -t "division_comunal" | psql -d gis_data_local -h localhost -U postgres
#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d gis_data -t "maestro_de_calles" -t "manzanas_1990" -t "permisos_vitacura" -t "poi_vitacura" -t "poi_vitacura_points" -t "prc_vitacura" -t "predios_1990" -t "predios_metropolitana" -t "predios_vitacura_2016" -t "superficie_areas_verdes_santiago" | psql -d gis_data_local -h localhost -U postgres

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d gis_data -t "anteproyectos_vitacura" -t "permisos_vitacura" -t "datos_predios_vitacura" -t "datos_roles_vitacura" | psql -d gis_data_local -h localhost -U postgres

#pg_dump -h localhost -U postgres -d landengines_local  --table="tabla_combinacion_predios" | psql -d landengines_dev -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev  -t  "tabla_resultados_cabidas" | psql -d landengines -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres
#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "combi_locations" -t "tabla_combinacion_predios" -t "tabla_resultados_cabidas" | psql -d landengines -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines -t "tabla_tipo_deptos" | psql -d landengines_dev -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres

#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d landengines_dev -t "combi_locations" -t "tabla_combinacion_predios" -t "tabla_resultados_cabidas" -t "tabla_tipo_deptos" | psql -d landengines_local -h localhost -U postgres