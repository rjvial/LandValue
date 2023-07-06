using LandValue, Distributed, DotEnv 

# run(`C:/Users/rjvia/Documents/Land_engines_code/Julia/key_code_host.bat`)
# run(`C:/Users/rjvia/Documents/Land_engines_code/Julia/key_code_user.bat`)
# run(`C:/Users/rjvia/Documents/Land_engines_code/Julia/key_code_pw.bat`)

    #[]
    #[151600124100010, 151600124100011, 151600124100012, 151600124100013, 151600124100014]
    #[151600135700004, 151600135700005, 151600135700016, 151600135700017, 151600135700021, 151600135700018, 151600135700019, 151600135700020] 
    #[151600048300017, 151600048300018, 151600048300049] 
    #[151600135100018, 151600135100019] 
    #[151600124100009, 151600124100010, 151600124100011, 151600124100012, 151600124100013, 151600124100014, 151600124100015]
    #[151600048300019, 151600048300004, 151600048300020, 151600048300021]
    #[151600048300004, 151600048300020, 151600048300021, 151600048300042, 151600048300043, 151600048300044]
    #[151600124100011, 151600124100012, 151600124100013, 151600124100014, 151600124100015]
    #[151600116900007, 151600116900008, 151600116900009, 151600116900013, 151600116900014, 151600116900098, 151600116900099, 151600116900100, 151600116900101]
    #[151600116900013, 151600116900014, 151600116900015, 151600116900099, 151600116900100, 151600116900101, 151600116900102, 151600116900103]
    #[151600116900013, 151600116900038, 151600116900102, 151600116900103, 151600116900036, 151600116900037]
    #[151600140900013, 151600140900014, 151600140900015, 151600140900017, 151600140900018, 151600140900019, 151600140900020, 151600140900021, 151600140900023, 151600140900024]
    #[151600187100049, 151600187100050, 151600187100048, 151600187100013, 151600187100014, 151600187100051, 151600187100052, 151600187100053, 151600187100015, 151600187100016, 151600187100054, 151600187100055]
    #[151600135700009, 151600135700003, 151600135700004, 151600135700005, 151600135700016, 151600135700017, 151600135700018, 151600135700019, 151600135700020]

let codigo_predial = []
    # Para cómputos sobre la base de datos usar codigo_predial = []

    tipoOptimizacion = "volumetrica"

    DotEnv.load("secrets.env") #Caso Docker
    datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    # datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
    # datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])



    if isempty(codigo_predial) # Cómputos sobre la base de datos

        query_check_resultados_cabidas_str = """
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'tabla_resultados_cabidas'
        """
        df_check_resultados_cabidas = pg_julia.query(conn_LandValue, query_check_resultados_cabidas_str)

        if isempty(df_check_resultados_cabidas) # En caso que no exista la tabla resultados_cabidas
            query_str = """ 
            CREATE TABLE IF NOT EXISTS public.tabla_resultados_cabidas
            (
                "combi_predios" text,
                "norma_max_num_deptos" double precision,
                "norma_max_ocupacion" double precision,
                "norma_max_constructibilidad" double precision,
                "norma_max_pisos" double precision,
                "norma_max_altura" double precision,
                "norma_min_estacionamientos_vendibles" double precision,
                "norma_min_estacionamientos_visita" double precision,
                "norma_min_estacionamientos_discapacitados" double precision,
                "cabida_temp_opt" int,
                "cabida_tipo_deptos" text,
                "cabida_num_deptos" text,
                "cabida_ocupacion" double precision,
                "cabida_constructibilidad" double precision,
                "cabida_num_pisos" double precision,
                "cabida_altura" double precision,
                "cabida_superficie_interior" double precision,
                "cabida_superficie_terraza" double precision,
                "cabida_superficie_comun" double precision,
                "cabida_superficie_edificada_snt" double precision,
                "cabida_superficie_por_piso" double precision,
                "cabida_estacionamientos_vendibles" double precision,
                "cabida_estacionamientos_visita" double precision,
                "cabida_num_estacionamientos" double precision,
                "cabida_num_bicicleteros" double precision,
                "cabida_num_bodegas" double precision,
                "terreno_superficie" double precision,
                "terreno_superficie_bruta" double precision,
                "terreno_largoFrenteCalle" double precision,
                "terreno_costo" double precision,
                "terreno_costo_unit" double precision,
                "terreno_costo_corredor" double precision,
                "terreno_costo_demolicion" double precision,
                "terreno_otros" double precision,
                "terreno_costo_total" double precision,
                "terreno_costo_unit_total" double precision,
                "holgura_ocupacion" double precision,
                "holgura_constructibilidad" double precision,
                "holgura_densidad" double precision,
                "indicador_ingresos_ventas" double precision,
                "indicador_costo_total" double precision,
                "indicador_margen_antes_impuesto" double precision,
                "indicador_impuesto_renta" double precision,
                "indicador_utilidad_despues_impuesto" double precision,
                "indicador_rentabilidad_total_bruta" double precision,
                "indicador_rentabilidad_total_neta" double precision,
                "indicador_incidencia_terreno" double precision,
                "optimo_solucion" text,
                "ps_predio" text, 
                "ps_vol_teorico" text, 
                "mat_conexion_vertices_vol_teorico" text, 
                "vecVertices_volTeorico" text, 
                "ps_volConSombra" text, 
                "mat_conexion_vertices_con_sombra" text,
                "vec_vertices_con_sombra" text, 
                "ps_publico" text, 
                "ps_calles" text, 
                "ps_base" text, 
                "ps_baseSeparada" text,
                "ps_predios_intra_buffer" text, 
                "ps_manzanas_intra_buffer" text, 
                "ps_calles_intra_buffer" text,
                "dx" double precision,
                "dy" double precision,
                id bigint NOT NULL
            )
            """
            pg_julia.query(conn_LandValue, query_str)
        end

        num_workers = 60 #
        addprocs(num_workers; exeflags="--project")
        @everywhere using LandValue, Distributed

        query_combinaciones_str = """
        select combi_predios_str, status, id from tabla_combinacion_predios order by id asc
        """
        df_combinaciones = pg_julia.query(conn_LandValue, query_combinaciones_str)
        df_combinaciones = filter(row -> row.status == 0, df_combinaciones)
        num_combi = size(df_combinaciones, 1)
        vec_combi = df_combinaciones[:,"id"]

        jobs = RemoteChannel(()->Channel{Any}(num_combi))
        function make_jobs(vec_combi) # Genera un numero n de jobs y los guarda en el channel jobs
            for j in eachindex(vec_combi)
                combi_j_str = df_combinaciones[j, 1]
                id_j = df_combinaciones[j, 3]
                codigo_predial = eval(Meta.parse(combi_j_str))
                put!(jobs, [tipoOptimizacion, codigo_predial, id_j, datos_LandValue, datos_mygis_db])
            end
        end
        
        results = RemoteChannel(()->Channel{Any}(num_combi))
        @everywhere function distributed_work(jobs, results) # Saca un job del channel y lo ejecuta, y después guarda el resultado en el channel results
            while true
                job_id = take!(jobs)
                tipoOptimizacion = job_id[1]
                codigo_predial = job_id[2]
                id = job_id[3]
                datos_LandValue = job_id[4]
                datos_mygis_db = job_id[5]
                display("***************************************************")
                display("* Ejecutando cabida predio: " * string(codigo_predial) * " en el Worker N° " * string(myid()))
                display("***************************************************")
                
                try
                    
                    temp_opt, alturaPiso, xopt, vec_datos, vecColumnNames, vecColumnValue, id = funcionPrincipal(tipoOptimizacion, codigo_predial, id, datos_LandValue, datos_mygis_db)
                    wkr = myid()
                    put!(results, (temp_opt, alturaPiso, xopt, vec_datos, vecColumnNames, vecColumnValue, id, wkr))

                catch error
                    display("")
                    display("#############################################################################")
                    display("#############################################################################")
                    display("# Se produjo un error, se proseguirá con la siguiente combinación de lotes. #")
                    display("#############################################################################")
                    display("#############################################################################")
                    display("")
                    display(id)
                    display("")

                
                    cond_str = "=" * string(id)
                    vecColumnNames = ["status", "id"]
                    vecColumnValue = ["19", string(id)]
                    
                    datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]                 
                    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
                    db_LandValue_str = datos_LandValue[1]
                    query_LandValue_pid = """
                                SELECT max(pid)
                                FROM pg_stat_activity
                                WHERE application_name = 'LibPQ.jl' AND datname = \'$db_LandValue_str\'
                            """
                    pid_landValue = pg_julia.query(conn_LandValue, query_LandValue_pid)[1, :max]
                    pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)
                    pg_julia.close_db(conn_LandValue)
                    query_kill_connections = """
                                SELECT pg_terminate_backend($pid_landValue)
                                FROM pg_stat_activity
                                WHERE pg_stat_activity.datname = \'$db_LandValue_str\'
                            """
                    pg_julia.query(conn_LandValue, query_kill_connections)
                end
            end
        end

        @async make_jobs(vec_combi)

        for p in workers() # start tasks on the workers to process requests in parallel
            #Executes f on worker id asynchronously. Unlike remotecall, it does not store 
            # the result of computation, nor is there a way to wait for its completion.
            remote_do(distributed_work, p, jobs, results) # Los parametros jobs, results son pasados a distributed_work()
        end

        cont = length(vec_combi)
        while cont > 0 # print out results

            
            temp_opt, alturaPiso, xopt, vec_datos, vecColumnNames, vecColumnValue, id, wkr = take!(results)
            pg_julia.insertRow!(conn_LandValue, "tabla_resultados_cabidas", vecColumnNames, vecColumnValue, :id)

            cond_str = "=" * string(id)
            vecColumnNames = ["status", "id"]
            vecColumnValue = ["1", string(id)]
            pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)
           
            display("")
            display(" Se agrego a la tabla_resultados_cabidas el resultado predio_id N° " *string(id) * " ejecutado por el worker N° " * string(wkr))
            display("")

            sleep(1)

            cont -= 1
        end

    else # Cómputos sobre los lotes específicos
        id_ = 0

        temp_opt, alturaPiso, xopt, vec_datos = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db)
       
        ps_predio = vec_datos[1]
        ps_volTeorico = vec_datos[2]
        matConexionVertices_volTeorico = vec_datos[3]
        vecVertices_volTeorico = vec_datos[4]
        ps_volConSombra = vec_datos[5]
        matConexionVertices_conSombra = vec_datos[6]
        vecVertices_conSombra = vec_datos[7]
        ps_publico = vec_datos[8] 
        ps_calles = vec_datos[9]
        ps_base = vec_datos[10]
        ps_baseSeparada = vec_datos[11]
        ps_calles_intra_buffer = vec_datos[12]
        ps_predios_intra_buffer = vec_datos[13]
        ps_manzanas_intra_buffer = vec_datos[14]
        ps_buffer_predio = vec_datos[15]
        dx = vec_datos[16]
        dy = vec_datos[17]
        ps_areaEdif = vec_datos[18]

    end
end

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

#pg_dump -h localhost -U postgres -d landengines_local -t "tabla_combinacion_predios"  | psql -d landengines_dev -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres
#pg_dump -h aws-landengines-db.cggiqowut9c4.us-east-1.rds.amazonaws.com -U postgres -d gis_data -t "anteproyectos_vitacura" -t "datos_predios_vitacura" -t "datos_roles_vitacura" -t "permisos_vitacura" | psql -d gis_data_local -h localhost -U postgres