using LandValue, Distributed, DotEnv

# Con Errores
# codigo_predial = [151600141900013, 151600141900014, 151600141900015, 151600141900024, 151600141900025, 151600141900026]
codigo_predial = [151600217300030, 151600217300031, 151600217300032, 151600217300051, 151600217300052, 151600217300053]
# codigo_predial = [151600048300004, 151600048300007, 151600048300020, 151600048300021, 151600048300042, 151600048300043, 151600048300044, 151600048300045, 151600048300046] # Tiene error
# codigo_predial = [151600340500128, 151600340500129, 151600340500130, 151600340500131, 151600340500132]

tipoOptimizacion = "volumetrica"

DotEnv.load("secrets.env")
datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
# datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])
id_ = 0

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