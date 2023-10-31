using LandValue, Distributed, DotEnv



let codigo_predial = [] 
    # Para cómputos sobre la base de datos usar codigo_predial = []
    tipoOptimizacion = "provisoria" #"economica"
    status_str = tipoOptimizacion == "economica" ? 2 : 1

    DotEnv.load("secrets.env") #Caso Docker
    datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
    # datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
    # datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

    conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
    conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])

    num_workers = length(Sys.cpu_info()) - 4 #1 #60 #
    addprocs(num_workers; exeflags="--project")
    @everywhere using LandValue, Distributed

    query_combinaciones_str = """
    select combi_predios_str, status, id from tabla_combinacion_predios 
    where status = $status_str
    order by id asc
    """
    df_combinaciones = pg_julia.query(conn_LandValue, query_combinaciones_str)

    vec_combi = df_combinaciones[:, "id"]
    num_combi = length(vec_combi)

    # Canal de información para contener los trabajos a realizar
    jobs = RemoteChannel(() -> Channel{Any}(num_combi))

    # Canal de información para contener los resultados de los trabajos realizados
    results = RemoteChannel(() -> Channel{Any}(num_combi))

    # Función que genera un numero n de jobs y los guarda en el channel jobs
    function make_jobs(vec_combi) 
        for j in eachindex(vec_combi)
            combi_j_str = df_combinaciones[j, "combi_predios_str"]
            id_j = df_combinaciones[j, "id"]
            codigo_predial = eval(Meta.parse(combi_j_str))
            put!(jobs, [tipoOptimizacion, codigo_predial, id_j, datos_LandValue, datos_mygis_db])
        end
    end

    # Función que saca un job del canal de trabajos, lo ejecuta, y después guarda el resultado en el canal de resultados
    @everywhere function distributed_work(jobs, results) 
        while true
            job_id = take!(jobs)
            tipoOptimizacion = job_id[1]
            codigo_predial = job_id[2]
            id = job_id[3]
            datos_LandValue = job_id[4]
            datos_mygis_db = job_id[5]
            display("***************************************************")
            display("* Ejecutando optimización económica combinación: " * string(codigo_predial) * " en el Worker N° " * string(myid()))
            display("***************************************************")

            try

                dcc, resultados, xopt, vecColumnNames, vecColumnValue, id, codigo_predial = funcionPrincipal(tipoOptimizacion, codigo_predial, id, datos_LandValue, datos_mygis_db)
                wkr = myid()
                put!(results, (dcc, resultados, xopt, vecColumnNames, vecColumnValue, id, codigo_predial, wkr))

                conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])

                pg_julia.modifyRow!(conn_LandValue, "tabla_resultados_cabidas", vecColumnNames, vecColumnValue, "combi_predios", "= \'" * string(codigo_predial) * "\'")
                sleep(1)
                cond_str = "=" * string(id)
                vecColumnNames_ = ["status", "id"]
                vecColumnValue_ = tipoOptimizacion == "economica" ? ["3", string(id)] : ["2", string(id)]
                pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames_, vecColumnValue_, "id", cond_str)
                sleep(1)
                pg_julia.close_db(conn_LandValue)
            
                display("")
                display(" Se agrego a la tabla_resultados_cabidas el resultado predio_id N° " * string(id) * " ejecutado por el worker N° " * string(wkr))
                display("")

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
                status_str = tipoOptimizacion == "economica" ? 39 : 29
                vecColumnValue = [string(status_str), string(id)]

                datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]                 
                conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])

                pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)
                pg_julia.close_db(conn_LandValue)
            end
        end
    end

    # Se generan los trabajos asociados a cada combinación de vec_combi
    @async make_jobs(vec_combi)

    # Se asigna cada trabajo a un worker
    for p in workers() 
        remote_do(distributed_work, p, jobs, results) # Los parametros jobs, results son pasados a distributed_work()
    end

    cont = length(vec_combi)
    while cont > 0 # print out results

        dcc, resultados, xopt, vecColumnNames, vecColumnValue, id, codigo_predial, wkr = take!(results)
        # pg_julia.modifyRow!(conn_LandValue, "tabla_resultados_cabidas", vecColumnNames, vecColumnValue, "combi_predios", "= \'" * string(codigo_predial) * "\'")

        # display("########## PASO POR ACA ")
        # sleep(1)

        # cond_str = "=" * string(id)
        # vecColumnNames_ = ["status", "id"]
        # vecColumnValue_ = ["1", string(id)]
        # pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames_, vecColumnValue_, "id", cond_str)
       
        # display("")
        # display(" Se agrego a la tabla_resultados_cabidas el resultado predio_id N° " *string(id) * " ejecutado por el worker N° " * string(wkr))
        # display("")

        sleep(1)

        cont -= 1
    end

end

# Para reinicializar tabla_resultados_cabidas
# update tabla_resultados_cabidas
# set norma_min_estacionamientos_vendibles = 0,
#     norma_min_estacionamientos_visita = 0,
#     norma_min_estacionamientos_discapacitados = 0,
#     cabida_tipo_deptos = 0,
#     cabida_num_deptos = 0,
#     cabida_ocupacion = 0,
#     cabida_constructibilidad = 0,
#     cabida_superficie_interior = 0,
#     cabida_superficie_terraza = 0,
#     cabida_superficie_comun = 0,
#     cabida_superficie_edificada_snt = 0,
#     cabida_superficie_por_piso = 0,
#     cabida_estacionamientos_vendibles = 0,
#     cabida_estacionamientos_visita = 0,
#     cabida_num_estacionamientos = 0,
#     cabida_num_bicicleteros = 0,
#     cabida_num_bodegas = 0,
#     terreno_costo = 0,
#     terreno_costo_unit = 0,
#     terreno_costo_corredor = 0,
#     terreno_costo_demolicion = 0,
#     terreno_otros = 0,
#     terreno_costo_total = 0,
#     terreno_costo_unit_total = 0,
#     holgura_ocupacion = 0,
#     holgura_constructibilidad = 0,
#     holgura_densidad = 0,
#     indicador_ingresos_ventas = 0,
#     indicador_costo_total = 0,
#     indicador_margen_antes_impuesto = 0,
#     indicador_impuesto_renta = 0,
#     indicador_utilidad_despues_impuesto = 0,
#     indicador_rentabilidad_total_bruta = 0,
#     indicador_rentabilidad_total_neta = 0,
#     indicador_incidencia_terreno = 0

# update tabla_combinacion_predios
# set status = 2
# where status = 3