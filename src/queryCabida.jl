module queryCabida

    using LandValue, ..pg_julia, ..polyShape

    function query_datos_predio(conn, comunaStr, codPredialStr)::Tuple{DatosCabidaNormativa, Float64, PolyShape}
        query_str = """
        SELECT codigo_predial, sup_terreno_edif, zona, densidad_bruta_hab_ha, densidad_neta_viv_ha, subdivision_predial_minima,
        coef_constructibilidad, ocupacion_suelo, ocupacion_pisos_superiores, coef_constructibilidad_continua, ocupacion_suelo_continua,
        ocupacion_pisos_superiores_continua, coef_area_libre, rasante, num_pisos_continua, altura_max_continua, num_pisos_sobre_edif_continua,
        altura_max_sobre_edif_continua, num_pisos_total, altura_max_total, antejardin_sobre_edif_continua, distanciamiento_sobre_edif_continua,
        antejardin, distanciamiento, ochavo, adosamiento_edif_continua, adosamiento_edif_aislada, ST_AsText(ST_Transform(geom_predios,5361)) as predios_str,
        area_calculada
        FROM datos_predios_comunaStr_
        WHERE codigo_predial IN codPredialStr_
        """
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        df = pg_julia.query(conn, query_str)
        num_rows = size(df,1)
        sup_terreno = df.sup_terreno_edif[:]
        prop_terreno = sup_terreno ./ sum(sup_terreno)
        dcn = LandValue.DatosCabidaNormativa()
        dcn.distanciamiento = sum(df.distanciamiento[:] .* prop_terreno)
        dcn.antejardin = sum(df.antejardin[:] .* prop_terreno)
        dcn.rasante = tan(minimum(df.rasante[:]) / 180*pi)
        alturaMax = df.altura_max_total[:]
        alturaMax[alturaMax .== -1] .= 100
        dcn.alturaMax = sum(alturaMax .* prop_terreno)
        maxPisos = df.num_pisos_total[:] 
        maxPisos[maxPisos .== -1] .= 30
        dcn.maxPisos = sum(maxPisos .* prop_terreno)
        dcn.coefOcupacion = sum(df.ocupacion_suelo[:] .* prop_terreno)
        dcn.supPredialMin = sum(df.subdivision_predial_minima[:] .* prop_terreno)
        dcn.densidadMax = sum(df.densidad_bruta_hab_ha[:] .* prop_terreno)
        dcn.coefConstructibilidad = sum(df.coef_constructibilidad[:] .* prop_terreno)
        
        sup_terreno_sii =  sum(df.sup_terreno_edif[:])
        predios_str = df.predios_str[:]
        ps = polyShape.astext2polyshape(predios_str)
        ps = polyShape.setPolyOrientation(ps,1)

        return dcn, sup_terreno_sii, ps
    end

    


    function query_buffer_predio(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """ 
        select ST_AsText(ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_))) as buffer_str
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        df_ = pg_julia.query(conn, query_str)
        ps_buffer_predio = polyShape.astext2polyshape(df_.buffer_str)
        ps_buffer_predio = polyShape.ajustaCoordenadas(ps_buffer_predio, dx, dy)
        ps_buffer_predio = polyShape.setPolyOrientation(ps_buffer_predio,1)

        return ps_buffer_predio
    end


    function query_predios_buffer(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """ 
        WITH buffer_predio AS (select ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_)) as geom
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_),
                predios_comuna AS (select ST_Transform(prediosStr_.geom_predios,5361) as geom, ST_AsText(ST_Transform(prediosStr_.geom_predios,5361)) as predios_str
                    from prediosStr_
                )
        select predios_comuna.predios_str
        from predios_comuna join buffer_predio on st_intersects(predios_comuna.geom, buffer_predio.geom)
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        query_str = replace(query_str, "comunaStrUpper_" => uppercase(comunaStr))
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "prediosStr_" => "datos_predios_" * lowercase(comunaStr))
        df_ = pg_julia.query(conn, query_str)
        ps_predios_buffer = polyShape.astext2polyshape(df_.predios_str)
        ps_predios_buffer = polyShape.ajustaCoordenadas(ps_predios_buffer, dx, dy)
        ps_predios_buffer = polyShape.polyUnique(ps_predios_buffer)
        ps_predios_buffer = polyShape.polyEliminateWithin(ps_predios_buffer)
        ps_predios_buffer = polyShape.setPolyOrientation(ps_predios_buffer,1)

        return ps_predios_buffer
    end


    function query_predios_intra_buffer(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """ 
        WITH buffer_predio AS (select ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_)) as geom
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_),
                    predios_comuna AS (select ST_Transform(prediosStr_.geom_predios,5361) as geom, ST_AsText(ST_Transform(prediosStr_.geom_predios,5361)) as predios_str
                    from prediosStr_)
        select  ST_AsText(st_intersection(predios_comuna.geom, buffer_predio.geom)) as predios_str
        from predios_comuna join buffer_predio on st_intersects(predios_comuna.geom, buffer_predio.geom)
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        query_str = replace(query_str, "comunaStrUpper_" => uppercase(comunaStr))
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "prediosStr_" => "datos_predios_" * lowercase(comunaStr))
        df_ = pg_julia.query(conn, query_str)
        ps_predios_intra_buffer = polyShape.astext2polyshape(df_.predios_str)
        ps_predios_intra_buffer = polyShape.ajustaCoordenadas(ps_predios_intra_buffer, dx, dy)
        ps_predios_intra_buffer = polyShape.polyUnique(ps_predios_intra_buffer)
        ps_predios_intra_buffer = polyShape.polyEliminateWithin(ps_predios_intra_buffer)
        ps_predios_intra_buffer = polyShape.setPolyOrientation(ps_predios_intra_buffer,1)

        return ps_predios_intra_buffer
    end


    function query_manzanas_buffer(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """
        WITH buffer_predio AS (select ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_)) as geom
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_
                    ),
              manzanas AS (select ST_Transform(datos_manzanas_vitacura_2017.geom, 5361) as manzanas_geom
              from datos_manzanas_vitacura_2017
              )
        select ST_AsText(manzanas.manzanas_geom) as buffer_manzana_str   
                    from manzanas join buffer_predio on st_intersects(manzanas.manzanas_geom, buffer_predio.geom)
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        df_ = pg_julia.query(conn, query_str)
        ps_manzanas_buffer = polyShape.astext2polyshape(df_.buffer_manzana_str)
        ps_manzanas_buffer = polyShape.ajustaCoordenadas(ps_manzanas_buffer, dx, dy)
        ps_manzanas_buffer = polyShape.setPolyOrientation(ps_manzanas_buffer,1)
        
        return ps_manzanas_buffer
    end


    function query_manzanas_intra_buffer(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """
        WITH buffer_predio AS (select ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_)) as geom
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_
                    ),
              manzanas AS (select ST_Transform(datos_manzanas_vitacura_2017.geom, 5361) as manzanas_geom
              from datos_manzanas_vitacura_2017
              )
        select ST_AsText(st_intersection(manzanas.manzanas_geom, buffer_predio.geom)) as buffer_manzana_str   
                    from manzanas join buffer_predio on st_intersects(manzanas.manzanas_geom, buffer_predio.geom)
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        df_ = pg_julia.query(conn, query_str)
        ps_manzanas_intra_buffer = polyShape.astext2polyshape(df_.buffer_manzana_str)
        ps_manzanas_intra_buffer = polyShape.ajustaCoordenadas(ps_manzanas_intra_buffer, dx, dy)
        ps_manzanas_intra_buffer = polyShape.setPolyOrientation(ps_manzanas_intra_buffer,1)
        
        return ps_manzanas_intra_buffer
    end


    function query_calles_intra_buffer(conn, comunaStr, codPredialStr, buffer_dist, dx, dy)
        query_str = """ 
        WITH buffer_predio AS (select ST_Union(ST_Buffer(ST_Transform(geom_predios,5361), bufferDistStr_)) as geom
                    from datos_predios_comunaStr_
                    where codigo_predial IN codPredialStr_
                    ),
            calles AS (select codigo as cod_calle, ST_Transform(mc.geom, 5361) as geom
                    from maestro_de_calles as mc 
                    where mc.comuna = '*comunaStr')
        select cod_calle, ST_AsText(st_intersection(buffer_predio.geom, calles.geom)) as calles_str
        from calles join buffer_predio on st_intersects(buffer_predio.geom, calles.geom)
        """
        bufferDistStr = string(buffer_dist)
        query_str = replace(query_str, "bufferDistStr_" => bufferDistStr)
        query_str = replace(query_str, "codPredialStr_" => codPredialStr)
        query_str = replace(query_str, "comunaStr_" => comunaStr)
        query_str = replace(query_str, "*comunaStr" => uppercase(comunaStr))
        df_ = pg_julia.query(conn, query_str)
        ls_calles = polyShape.astext2lineshape(df_.calles_str)
        ls_calles = polyShape.ajustaCoordenadas(ls_calles, dx, dy)

        return ls_calles
    end


    export query_datos_predio, query_buffer_predio, query_predios_buffer, query_predios_intra_buffer, query_manzanas_buffer, 
    query_manzanas_intra_buffer, query_calles_intra_buffer

end
