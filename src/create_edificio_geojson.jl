function create_edificio_geojson(xopt, ps_predio, ps_base, ps_areaEdif, alturaPiso, dx, dy, file_str)
    # create_edificio_geojson(xopt, ps_predio, ps_base, ps_areaEdif, alturaPiso, dx, dy, "edificio_test.geojson")
    
    numPisos = Int(xopt[1])

    EPSG_in = 5361
    EPSG_out = 4326

    
    ps_base_ = polyShape.polyCopy(ps_base)
    ps_predio_ = polyShape.polyCopy(ps_predio)
    ps_areaEdif_ = polyShape.polyCopy(ps_areaEdif)

    str_capa = ""

    poly_predio = polyShape.polyReproject(ps_predio_, dx, dy, EPSG_in, EPSG_out)
    str_geom_predio = ArchGDAL.toJSON(poly_predio)
    level_str = 0
    name_str = "\"Predio\""
    height_predio_ini = 0
    height_predio_fin = 0
    str_predio = """
    {
            "type": "Feature",
            "properties": {
                "level": $level_str,
                "name": $name_str,
                "height": $height_predio_fin,
                "base_height": $height_predio_ini,
                "color": "gray"
            },
            "geometry": str_geom_predio__
        },
    """
    str_predio = replace(str_predio, "str_geom_predio__" => str_geom_predio)
    str_capa = str_capa * str_predio


    poly_areaEdif = polyShape.polyReproject(ps_areaEdif_, dx, dy, EPSG_in, EPSG_out)
    str_geom_areaEdif = ArchGDAL.toJSON(poly_areaEdif)
    level_str = 0
    name_str = "\"Area Edificación\""
    height_areaEdif_ini = 0.1
    height_areaEdif_fin = 0.1
    str_areaEdif = """
    {
            "type": "Feature",
            "properties": {
                "level": $level_str,
                "name": $name_str,
                "height": $height_areaEdif_fin,
                "base_height": $height_areaEdif_ini,
                "color": "#404040"
            },
            "geometry": str_geom_areaEdif__
        },
    """
    str_areaEdif = replace(str_areaEdif, "str_geom_areaEdif__" => str_geom_areaEdif)
    str_capa = str_capa * str_areaEdif


    poly_base = polyShape.polyReproject(ps_base_, dx, dy, EPSG_in, EPSG_out)
    str_geom_base = ArchGDAL.toJSON(poly_base)

    for i = 1:numPisos
        level_str = i
        name_str = "\"Piso Nivel $i\""
        height_muros_ini = alturaPiso * (i - 1)
        height_muros_fin = alturaPiso * i
        
        if i == numPisos
            str_coma = ""
        else
            str_coma = ","
        end
        
        height_piso_ini = height_muros_ini
        height_piso_fin = height_muros_ini + 0.2
        str_piso_i = """
        {
                "type": "Feature",
                "properties": {
                    "level": $level_str,
                    "name": $name_str,
                    "height": $height_piso_fin,
                    "base_height": $height_piso_ini,
                    "color": "black"
                },
                "geometry": str_geom_bases__
            },
        """
        str_piso_i = replace(str_piso_i, "str_geom_bases__" => str_geom_base)
        str_capa = str_capa * str_piso_i

        name_str = "\"Muros Nivel $i\""
        str_capa_i = """
        {
                "type": "Feature",
                "properties": {
                    "level": $level_str,
                    "name": $name_str,
                    "height": $height_muros_fin,
                    "base_height": $height_muros_ini,
                    "color": "#467e52"
                },
                "geometry": str_geom_bases__
            }$str_coma
        """
        str_capa_i = replace(str_capa_i, "str_geom_bases__" => str_geom_base)
        str_capa = str_capa * str_capa_i
    end

    str_final ="""
    {
    "features": [ $str_capa
    ],
    "type": "FeatureCollection"
    }
    """
    
    open(file_str, "w") do f
        write(f, str_final)
    end
    
    
end