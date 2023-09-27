using LandValue, Distributed, DotEnv

# [151600217300030, 151600217300031, 151600217300051, 151600217300052, 151600217300053]
# [151600140500007, 151600140500008, 151600140500009, 151600140500019, 151600140500020, 151600140500021, 151600140500028, 151600140500029, 151600140500030, 151600140500031, 151600140500032]
# [151600140500019, 151600140500020, 151600140500021, 151600140500022, 151600140500023, 151600140500028, 151600140500029, 151600140500030]
# [151600143500043, 151600143500044, 151600143500057, 151600143500058, 151600143500059, 151600143500060]
# [151600143500043, 151600143500044, 151600143500057, 151600143500058, 151600143500059, 151600143500060, 151600143500061, 151600143500062, 151600143500063, 151600143500064]
# [151600143500043, 151600143500044, 151600143500046, 151600143500047, 151600143500054, 151600143500055, 151600143500056, 151600143500057, 151600143500058, 151600143500059, 151600143500060]
# [151600048300007, 151600048300042, 151600048300043, 151600048300044, 151600048300045, 151600048300046]
# [151600052300001, 151600052300002, 151600052300019, 151600052300020, 151600052300021, 151600052300024]

codigo_predial = [151600217300030, 151600217300031, 151600217300051, 151600217300052, 151600217300053]


tipoOptimizacion = "volumetrica"

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

id_ = 0

fpe, temp_opt, alturaPiso, xopt, vec_datos, superficieTerreno, superficieTerrenoBruta = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db, [])


ps_predio = vec_datos[1]
verts = vec_datos[2]
verts_conSombra = vec_datos[3]
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


fig, ax, ax_mat = plotBaseEdificio3D(fpe, xopt, alturaPiso, ps_predio, verts, verts_conSombra, ps_publico, ps_calles, ps_base, ps_baseSeparada, ps_primerPiso)

fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_predios_intra_buffer, 0.0, "green", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_manzanas_intra_buffer, 0.0, "red", 0.1, fig=fig, ax=ax, ax_mat=ax_mat)
fig, ax, ax_mat = polyShape.plotPolyshape2Din3D(ps_buffer_predio, 0.0, "gray", 0.15, fig=fig, ax=ax, ax_mat=ax_mat)


# datos contiene la información necesaria para correr la Evaluación Económica
datos = [xopt[1]*alturaPiso, ps_base, superficieTerreno, superficieTerrenoBruta, xopt, ps_areaEdif]


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