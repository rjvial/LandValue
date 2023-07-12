using LandValue, DotEnv 

DotEnv.load("secrets.env") #Caso Docker
# datos_LandValue = ["landengines_dev", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_mygis_db = ["gis_data", ENV["USER_AWS"], ENV["PW_AWS"], ENV["HOST_AWS"]]
datos_LandValue = ["landengines_local", "postgres", "", "localhost"]
# datos_mygis_db = ["gis_data_local", "postgres", "", "localhost"]

conn_LandValue = pg_julia.connection(datos_LandValue[1], datos_LandValue[2], datos_LandValue[3], datos_LandValue[4])
conn_mygis_db = pg_julia.connection(datos_mygis_db[1], datos_mygis_db[2], datos_mygis_db[3], datos_mygis_db[4])


let codigo_predial = [] #[151600135100018, 151600135100019] #[151600124100009, 151600124100010, 151600124100011, 151600124100012, 151600124100013, 151600124100014, 151600124100015] 
    # Para cómputos sobre la base de datos usar codigo_predial = []
    tipoOptimizacion = "provisoria" #"economica"

    if isempty(codigo_predial)

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
                id bigint NOT NULL,
                CONSTRAINT tabla_resultados_cabidas_pkey PRIMARY KEY (id)
            )
            """
            pg_julia.query(conn_LandValue, query_str)
        end
        
        # "cabida_num_deptosTipo" double precision,
        # "optimo_template" int,
        
        
        query_combinaciones_str = """
        select combi_predios_str, status, id from tabla_combinacion_predios order by id asc
        """
        df_combinaciones = pg_julia.query(conn_LandValue, query_combinaciones_str)
        df_combinaciones = filter(row -> row.status <= 1, df_combinaciones)
        
        num_combi = size(df_combinaciones,1)
        for i = 1:num_combi
            combi_i_str = df_combinaciones[i,1]
            id_i = df_combinaciones[i,"id"]
            display("***************************************************")
            display("* Ejecutando cabida predio: " * combi_i_str)
            display("***************************************************")
            codigo_predial = eval(Meta.parse(combi_i_str))
        
            # try
                        
                # Etapa 2-B: Ejecuta optimización Económica y presenta resumen de resultados 
                
                @time dcc, resultados = funcionPrincipal(tipoOptimizacion, codigo_predial, id_i, datos_LandValue, datos_mygis_db);
        
                displayResults(resultados, dcc)
                println(" ")
                println(" ")
                println(" ")
        
                cond_str = "=" * string(id_i)
                vecColumnNames = ["status", "id"]
                vecColumnValue = ["2", string(id_i)]
                pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)    
        
            # catch error
            #     display("")
            #     display("#############################################################################")
            #     display("#############################################################################")
            #     display("# Se produjo un error, se proseguirá con la siguiente combinación de lotes. #")
            #     display("#############################################################################")
            #     display("#############################################################################")
            #     display("")
        
            #     cond_str = "=" * string(id_i)
            #     vecColumnNames = ["status", "id"]
            #     vecColumnValue = ["29", string(id_i)]
            #     pg_julia.modifyRow!(conn_LandValue, "tabla_combinacion_predios", vecColumnNames, vecColumnValue, "id", cond_str)    
        
            # end
        end
    else
        id_ = 0

        dcc, resultados, xopt = funcionPrincipal(tipoOptimizacion, codigo_predial, id_, datos_LandValue, datos_mygis_db)

        displayResults(resultados, dcc)

    end
        
end

