# Constants for better maintainability
const INTERIOR_FACTOR = 0.95
const TERRACE_FACTOR = 0.10
const COMMON_AREAS_FACTOR = 0.20
const DENSITY_DIVISOR = 4
const AREA_CONVERSION = 10000
const DEFAULT_FLOOR_BUFFER = 2
const MIN_FLOORS = 3
const OFFICE_AREA_PER_UNIT = 100
const BODEGA_RATIO = 0.2
const DEFAULT_OCCUPATION_LOAD = 100
const DEFAULT_METRO_DISTANCE = 3000
const COEF_OCUPACION_EST = 1.0
const LARGE_NUMBER = 999999


function python_expression_eval_with_varmap(expr_dict, variable_map::Dict{String, <:Any})
    # Evaluates Python expressions with variable substitution and proper error handling.

    try
        expr_str = expression_converter.parse_python_expression(expr_dict[3])
        
        # Apply variable substitutions
        for (var_name, var_value) in variable_map
            expr_str = replace(expr_str, var_name => string(var_value))
        end
        
        return eval(Meta.parse(expr_str))
    catch e
        @warn "Expression evaluation failed: $e"
        throw(ArgumentError("Invalid expression in requirements: $(expr_dict[3])"))
    end
end


function opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    # ============================================================================
    # MAIN BUILDING OPTIMIZATION FUNCTION
    # ============================================================================
        
    # ============================================================================
    # 1. BUILDING CONFIGURATION SETUP
    # ============================================================================
    config_edificio = Dict{String, Any}()
    
    # Building type flags
    config_edificio["tipo_edificio"] = dict_arquitectura["tipo_edificio"]
    variante_str = dict_arquitectura["variante_normativa"]
    config_edificio["variante_str"] = variante_str
    config_edificio["flag_dfl2"] = (variante_str == "dfl_2")
    config_edificio["flag_economica"] = (variante_str == "vivienda_economica")

    # Surface areas
    config_edificio["superficieTerreno"] = dict_geom["sup_terreno_sii"]
    config_edificio["superficieTerrenoBruto"] = polyShape.polyArea(dict_geom["ps_bruto"])

    # Constructibility calculation
    coef_const_raw = dict_requerimientos["coeficiente_de_constructibilidad"]
    if typeof(coef_const_raw[1]) == Float64
        config_edificio["coefConstructibilidad"] = coef_const_raw[1]
    else
        variable_map = Dict(
            "n_predios" => dict_geom["n_predios"],
            "coeficiente_de_constructibilidad" => parse(Float64, coef_const_raw[1])
        )
        config_edificio["coefConstructibilidad"] = python_expression_eval_with_varmap(coef_const_raw, variable_map)
    end
    
    config_edificio["max_constructibilidad"] = config_edificio["superficieTerreno"] * config_edificio["coefConstructibilidad"]
    
    # Calculate max losa based on building type and variant
    base_constructibilidad = config_edificio["max_constructibilidad"]
    is_apartment_special = (config_edificio["tipo_edificio"] == "departamento" &&
                           (config_edificio["flag_dfl2"] || config_edificio["flag_economica"]))

    if is_apartment_special
        config_edificio["max_losa_snt"] = base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR + COMMON_AREAS_FACTOR)
    else
        config_edificio["max_losa_snt"] = base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR)
    end
    
    # Floor configuration
    maxPisos = dict_requerimientos["n_pisos"]
    config_edificio["maxPisos"] = maxPisos
    config_edificio["default_min_pisos"] = max(MIN_FLOORS, maxPisos - DEFAULT_FLOOR_BUFFER)
    config_edificio["vec_pisos"] = collect(config_edificio["default_min_pisos"]:maxPisos)

    # ============================================================================
    # 2. DENSITY AND OCCUPATION CALCULATIONS
    # ============================================================================
    density_config = Dict{String, Any}()
    
    # Density calculation
    flagDensidadBruta = haskey(dict_requerimientos, "densidad_maxima_bruta")
    density_config["flagDensidadBruta"] = flagDensidadBruta

    superficie_densidad = flagDensidadBruta ? config_edificio["superficieTerrenoBruto"] : config_edificio["superficieTerreno"]
    max_densidad = flagDensidadBruta ? dict_requerimientos["densidad_maxima_bruta"] : dict_requerimientos["densidad_maxima_neta"]
    
    density_config["max_deptos"] = floor(max_densidad / DENSITY_DIVISOR * superficie_densidad / AREA_CONVERSION)
    
    # Ground occupation
    sup_patio_vivienda_economica = config_edificio["flag_economica"] ? dict_requerimientos["superficice_min_patio_x_depto"] : 0
    ocupacion_suelo = dict_requerimientos["coeficiente_de_ocupacion_de_suelo"]
    
    density_config["sup_patio_vivienda_economica"] = sup_patio_vivienda_economica
    if config_edificio["flag_economica"]
        density_config["max_ocupacion_suelo"] = config_edificio["superficieTerreno"] - density_config["max_deptos"] * sup_patio_vivienda_economica
    else
        density_config["max_ocupacion_suelo"] = config_edificio["superficieTerreno"] * ocupacion_suelo
    end

    
    # ============================================================================
    # 3. VOLUME OPTIMIZATION
    # ============================================================================
    vec_pisos, max_ocupacion_suelo, max_losa_snt = config_edificio["vec_pisos"], density_config["max_ocupacion_suelo"], config_edificio["max_losa_snt"]
    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra, 
    ps_sombraEdif_p, ps_sombraEdif_o, ps_sombraEdif_s, 
    ps_sombraVolTeorico_p, ps_sombraVolTeorico_o, ps_sombraVolTeorico_s = opti_edificio_vol(dict_geom, dict_arquitectura, dict_requerimientos, vec_pisos, 
                                                                                            max_ocupacion_suelo, max_losa_snt)

    # ============================================================================
    # 4. APARTMENT CONFIGURATION
    # ============================================================================
    if config_edificio["tipo_edificio"] == "departamento"
        dict_edificio_deptos = opti_edificio_deptos(dict_arquitectura, config_edificio["max_constructibilidad"], density_config["max_deptos"], 
                                                    vec_ps_opt, vec_np_opt, config_edificio["flag_dfl2"], 
                                                    density_config["sup_patio_vivienda_economica"], config_edificio["superficieTerreno"])
    else
        dict_edificio_deptos = Dict{String, Any}("numDeptosTipo" => [0], "supUtil" => 0.0, "supNoUtilizada" => 0.0)
    end
    
    # ============================================================================
    # 5. CAPACITY DATA CALCULATION
    # ============================================================================
    cabida_data = Dict{String, String}()
    
    if config_edificio["tipo_edificio"] == "departamento"
        cabida_data["cabida_sup_deptos"] = string(get(dict_arquitectura, "vecSupUtil", "0"))
        cabida_data["cabida_num_deptos"] = string(dict_edificio_deptos["numDeptosTipo"])
        cabida_data["cabida_sup_comercio"] = "0"
        cabida_data["cabida_num_comercio"] = "0"
        cabida_data["cabida_sup_oficinas"] = "0"
        cabida_data["cabida_num_oficinas"] = "0"
    else
        # Safely calculate area, handling empty polygons
        area_edif = 0.0
        for i in eachindex(vec_ps_opt)
            if !isempty(vec_ps_opt[i].Vertices)
                area_edif += polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i]
            end
        end
        cabida_data["cabida_sup_deptos"] = "0"
        cabida_data["cabida_num_deptos"] = "0"
        cabida_data["cabida_sup_comercio"] = "0"
        cabida_data["cabida_num_comercio"] = "0"
        cabida_data["cabida_sup_oficinas"] = string(OFFICE_AREA_PER_UNIT)
        cabida_data["cabida_num_oficinas"] = string(ceil(area_edif / OFFICE_AREA_PER_UNIT))
    end

    # ============================================================================
    # 6. PARKING REQUIREMENTS CALCULATION
    # ============================================================================
    parking_data = Dict{String, Any}()
    
    try
        # Car parking calculations
        car_parking_vars = Dict(
            "cabida_sup_deptos" => cabida_data["cabida_sup_deptos"],
            "cabida_num_deptos" => cabida_data["cabida_num_deptos"],
            "cabida_sup_comercio" => cabida_data["cabida_sup_comercio"],
            "cabida_num_comercio" => cabida_data["cabida_num_comercio"],
            "cabida_sup_oficinas" => cabida_data["cabida_sup_oficinas"],
            "cabida_num_oficinas" => cabida_data["cabida_num_oficinas"]
        )
        
        dict_estacionamientos = python_expression_eval_with_varmap(dict_requerimientos["estacionamientos_autos"], car_parking_vars)
        parking_data["estacionamientos_autos_oficina"] = Float64(dict_estacionamientos["estacionamientos_autos_oficina"])
        parking_data["estacionamientos_autos_vivienda"] = Float64(dict_estacionamientos["estacionamientos_autos_vivienda"])
        parking_data["estacionamientos_autos_comercio"] = Float64(dict_estacionamientos["estacionamientos_autos_comercio"])
        parking_data["estacionamientos_autos"] = parking_data["estacionamientos_autos_oficina"] + 
                                          parking_data["estacionamientos_autos_vivienda"] + 
                                          parking_data["estacionamientos_autos_comercio"]
        
        # Visitor parking
        visitor_vars = Dict("estacionamientos_autos_vivienda" => parking_data["estacionamientos_autos_vivienda"])
        parking_data["estacionamientos_visitas"] = Float64(python_expression_eval_with_varmap(dict_requerimientos["estacionamientos_visitas"], visitor_vars))
        
        # Total parking spots
        numEst = parking_data["estacionamientos_autos"] + parking_data["estacionamientos_visitas"]
        
        # Disabled parking
        disabled_vars = Dict("estacionamientos_autos" => numEst)
        parking_data["estacionamientos_discapacitados"] = Float64(python_expression_eval_with_varmap(dict_requerimientos["estacionamientos_discapacitados"], disabled_vars))
        
        # Bicycle parking
        bike_vars = Dict(
            "estacionamientos_autos" => parking_data["estacionamientos_autos"],
            "estacionamientos_visitas" => parking_data["estacionamientos_visitas"],
            "carga_ocupacion" => DEFAULT_OCCUPATION_LOAD
        )
        parking_data["estacionamientos_bicicletas"] = Float64(python_expression_eval_with_varmap(dict_requerimientos["estacionamientos_bicicletas"], bike_vars))
        
        # Metro discount
        metro_vars = Dict(
            "estacionamientos_autos_vivienda" => parking_data["estacionamientos_autos_vivienda"],
            "estacionamientos_autos_comercio" => parking_data["estacionamientos_autos_comercio"],
            "estacionamientos_autos_oficina" => parking_data["estacionamientos_autos_oficina"],
            "distancia_al_metro" => DEFAULT_METRO_DISTANCE
        )
        parking_data["descuento_estacionamientos_x_metro"] = Float64(python_expression_eval_with_varmap(dict_requerimientos["descuento_estacionamientos_x_metro"], metro_vars))

        # Bicycle discount
        bike_discount_vars = Dict(
            "estacionamientos_autos" => parking_data["estacionamientos_autos"],
            "estacionamientos_visitas" => parking_data["estacionamientos_visitas"],
            "descuento_estacionamientos_x_metro" => parking_data["descuento_estacionamientos_x_metro"],
            "estacionamientos_bicicletas" => parking_data["estacionamientos_bicicletas"]
        )
        
        dict_descuento_bici = python_expression_eval_with_varmap(dict_requerimientos["descuento_estacionamientos_x_bici"], bike_discount_vars)
        parking_data["descuento_estacionamientos_x_bici_t1"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici_t1"])
        parking_data["descuento_estacionamientos_x_bici_t2"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici_t2"])
        parking_data["descuento_estacionamientos_x_bici"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici"])

        # Bicycle increase from discount
        bike_increase_vars = Dict("descuento_estacionamientos_x_bici_t2" => parking_data["descuento_estacionamientos_x_bici_t2"])
        parking_data["aumento_bici_x_descuento_estacionamientos"] = python_expression_eval_with_varmap(dict_requerimientos["aumento_bici_x_descuento_estacionamientos"], bike_increase_vars)

        # Final calculations
        parking_data["estacionamientos_autos_final"] = parking_data["estacionamientos_autos"] + parking_data["estacionamientos_visitas"] - 
                                                 parking_data["descuento_estacionamientos_x_metro"] - parking_data["descuento_estacionamientos_x_bici"]
        parking_data["estacionamientos_bicicletas_final"] = parking_data["estacionamientos_bicicletas"] + parking_data["aumento_bici_x_descuento_estacionamientos"]

    catch e
        @warn "Error calculating parking requirements: $e"
        # Set minimal parking configuration
        parking_data = Dict{String, Any}(
            "estacionamientos_autos_oficina" => 0.0,
            "estacionamientos_autos_vivienda" => 0.0,
            "estacionamientos_autos_comercio" => 0.0,
            "estacionamientos_autos" => 0.0,
            "estacionamientos_visitas" => 0.0,
            "estacionamientos_discapacitados" => 0.0,
            "estacionamientos_bicicletas" => 0.0,
            "descuento_estacionamientos_x_metro" => 0.0,
            "descuento_estacionamientos_x_bici_t1" => 0.0,
            "descuento_estacionamientos_x_bici_t2" => 0.0,
            "descuento_estacionamientos_x_bici" => 0.0,
            "aumento_bici_x_descuento_estacionamientos" => 0.0,
            "estacionamientos_autos_final" => 0.0,
            "estacionamientos_bicicletas_final" => 0.0
        )
    end
    
    # ============================================================================
    # 7. STORAGE AND UNDERGROUND AREA CALCULATION
    # ============================================================================
    numBodegas = if config_edificio["tipo_edificio"] == "departamento"
        sum(dict_edificio_deptos["numDeptosTipo"])
    else
        ceil(BODEGA_RATIO * (parking_data["estacionamientos_autos_final"] + parking_data["estacionamientos_visitas"]))
    end
    
    # Calculate underground area requirements
    supPorEstacionamiento = dict_arquitectura["supPorEstacionamiento"]
    supPorBodega = dict_arquitectura["supPorBodega"]
    supPorBicicleta = dict_arquitectura["supPorBicicleta"]
    
    areaEst_requerida = parking_data["estacionamientos_autos_final"] * supPorEstacionamiento + 
                            parking_data["estacionamientos_bicicletas_final"] * supPorBicicleta + 
                            numBodegas * supPorBodega

    # Create underground area polygon
    vecSecTodos = dict_geom["vecSecTodos"]
    vecSecSinCalle = dict_geom["vecSecSinCalle"]
    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -dict_requerimientos["subterraneo_antejardin"]
    vec_dist[vecSecSinCalle] .= -dict_requerimientos["subterraneo_distanciamiento"]
    
    ps_predio = deepcopy(dict_geom["ps_combi"])
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)
    
    
    # ============================================================================
    # 8. UNDERGROUND VOLUME OPTIMIZATION
    # ============================================================================
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(dict_geom["ps_combi"], ps_areaEst, COEF_OCUPACION_EST, areaEst_requerida)

    # ============================================================================
    # 9. RESULTS COMPILATION
    # ============================================================================
    dict_resultados = OrderedDict(
        "tipo_edificio" => config_edificio["tipo_edificio"],
        "variante_normativa" => config_edificio["variante_str"],
        "flag_sombra" => dict_arquitectura["flag_sombra"],
        "sup_edificada_snt" => max_sol,
        "pisos_snt" => sum(vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "sup_edificada_bnt" => areaEst_requerida,
        "pisos_bnt" => 0,
        "cabida_sup_deptos" => cabida_data["cabida_sup_deptos"],
        "cabida_num_deptos" => cabida_data["cabida_num_deptos"],
        "cabida_sup_comercio" => cabida_data["cabida_sup_comercio"],
        "cabida_num_comercio" => cabida_data["cabida_num_comercio"],
        "cabida_sup_oficinas" => cabida_data["cabida_sup_oficinas"],
        "cabida_num_oficinas" => cabida_data["cabida_num_oficinas"],
        "estacionamientos_autos_oficina" => parking_data["estacionamientos_autos_oficina"],
        "estacionamientos_autos_vivienda" => parking_data["estacionamientos_autos_vivienda"],
        "estacionamientos_autos_comercio" => parking_data["estacionamientos_autos_comercio"],
        "estacionamientos_autos" => parking_data["estacionamientos_autos"],
        "estacionamientos_visitas" => parking_data["estacionamientos_visitas"],
        "estacionamientos_discapacitados" => parking_data["estacionamientos_discapacitados"],
        "estacionamientos_bicicletas" => parking_data["estacionamientos_bicicletas"],
        "descuento_estacionamientos_x_metro" => parking_data["descuento_estacionamientos_x_metro"],
        "descuento_estacionamientos_x_bici_t1" => parking_data["descuento_estacionamientos_x_bici_t1"],
        "descuento_estacionamientos_x_bici_t2" => parking_data["descuento_estacionamientos_x_bici_t2"],
        "descuento_estacionamientos_x_bici" => parking_data["descuento_estacionamientos_x_bici"],
        "aumento_bici_x_descuento_estacionamientos" => parking_data["aumento_bici_x_descuento_estacionamientos"],
        "estacionamientos_autos_final" => parking_data["estacionamientos_autos_final"],
        "estacionamientos_bicicletas_final" => parking_data["estacionamientos_bicicletas_final"],
        "bodegas" => numBodegas,
        "dict_edificio_deptos" => config_edificio["tipo_edificio"] == "departamento" ? dict_edificio_deptos : 0,
        "vec_ps_opt" => vec_ps_opt,
        "vec_np_opt" => vec_np_opt,
        "vec_ps_subte" => vec_ps_subte,
        "vec_np_subte" => vec_np_subte,
        "vec_psVolteor" => vec_psVolteor,
        "vec_altVolteor" => vec_altVolteor,
        "vec_psVolConSombra" => vec_psVolConSombra,
        "vec_altVolConSombra" => vec_altVolConSombra,
        "ps_sombraEdif_p" => ps_sombraEdif_p,
        "ps_sombraEdif_o" => ps_sombraEdif_o,
        "ps_sombraEdif_s" => ps_sombraEdif_s,
        "ps_sombraVolTeorico_p" => ps_sombraVolTeorico_p,
        "ps_sombraVolTeorico_o" => ps_sombraVolTeorico_o,
        "ps_sombraVolTeorico_s" => ps_sombraVolTeorico_s
    )

    dict_proyecto_vs_normativa = OrderedDict(
        "densidad_proyecto" => sum(eval(Meta.parse(cabida_data["cabida_num_deptos"]))),
        "densidad_normativa" => density_config["max_deptos"],
        "losa_proyecto" => sum(isempty(vec_ps_opt[i].Vertices) ? 0.0 : polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "losa_normativa" => config_edificio["flag_economica"] ? LARGE_NUMBER : config_edificio["max_losa_snt"],
        "constructibilidad_proyecto" => dict_edificio_deptos["supUtil"],
        "constructibilidad_normativa" => config_edificio["flag_economica"] ? LARGE_NUMBER : config_edificio["max_constructibilidad"],
        "ocupacion_suelo_proyecto" => isempty(vec_ps_opt) || isempty(vec_ps_opt[1].Vertices) ? 0.0 : polyShape.polyArea(vec_ps_opt[1]),
        "ocupacion_suelo_normativa" => if config_edificio["flag_economica"]
                                        config_edificio["superficieTerreno"] - sum(eval(Meta.parse(cabida_data["cabida_num_deptos"]))) * density_config["sup_patio_vivienda_economica"]
                                    else
                                        density_config["max_ocupacion_suelo"]
                                    end,
        "pisos_proyecto" => sum(vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "pisos_normativa" => dict_requerimientos["n_pisos"],
        "supNoUtilizada" => dict_edificio_deptos["supNoUtilizada"]
    )

    return dict_resultados, dict_proyecto_vs_normativa
end