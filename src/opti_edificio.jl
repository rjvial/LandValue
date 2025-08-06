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

"""
    validate_opti_edificio_inputs(dict_geom, dict_arquitectura, dict_requerimientos)

Validates input parameters for building optimization.
"""
function validate_opti_edificio_inputs(dict_geom, dict_arquitectura, dict_requerimientos)
    # Validate required keys
    required_geom_keys = ["sup_terreno_sii", "ps_bruto", "ps_predio", "vecSecTodos", "vecSecSinCalle"]
    required_arq_keys = ["tipo_edificio", "variante_normativa", "alturaPiso", "K", "flag_sombra"]
    required_req_keys = ["coeficiente_de_constructibilidad", "n_pisos", "coeficiente_de_ocupacion_de_suelo"]
    
    for key in required_geom_keys
        haskey(dict_geom, key) || throw(ArgumentError("Missing required geometry key: $key"))
    end
    
    for key in required_arq_keys
        haskey(dict_arquitectura, key) || throw(ArgumentError("Missing required architecture key: $key"))
    end
    
    for key in required_req_keys
        haskey(dict_requerimientos, key) || throw(ArgumentError("Missing required requirements key: $key"))
    end
    
    # Validate values
    dict_geom["sup_terreno_sii"] > 0 || throw(ArgumentError("Surface area must be positive"))
    dict_arquitectura["alturaPiso"] > 0 || throw(ArgumentError("Floor height must be positive"))
    dict_arquitectura["K"] > 0 || throw(ArgumentError("Number of stacks must be positive"))
    dict_requerimientos["n_pisos"] > 0 || throw(ArgumentError("Max floors must be positive"))
end

"""
    safe_expression_eval(expr_dict, variable_map)

Safely evaluates Python expressions with variable substitution and proper error handling.
"""
function safe_expression_eval(expr_dict, variable_map::Dict{String, <:Any})
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

"""
    calculate_building_config(dict_geom, dict_arquitectura, dict_requerimientos)

Calculates basic building configuration parameters.
Returns dictionary with configuration values.
"""
function calculate_building_config(dict_geom, dict_arquitectura, dict_requerimientos)
    config = Dict{String, Any}()
    
    # Building type flags
    config["tipo_edificio"] = dict_arquitectura["tipo_edificio"]
    variante_str = dict_arquitectura["variante_normativa"]
    config["variante_str"] = variante_str
    config["flag_dfl2"] = (variante_str == "dfl_2")
    config["flag_economica"] = (variante_str == "vivienda_economica")
    
    # Surface areas
    config["superficieTerreno"] = dict_geom["sup_terreno_sii"]
    config["superficieTerrenoBruto"] = polyShape.polyArea(dict_geom["ps_bruto"])
    
    # Constructibility calculation
    coef_const_raw = dict_requerimientos["coeficiente_de_constructibilidad"]
    if typeof(coef_const_raw[1]) == Float64
        config["coefConstructibilidad"] = coef_const_raw[1]
    else
        variable_map = Dict(
            "n_predios" => dict_geom["n_predios"],
            "coeficiente_de_constructibilidad" => parse(Float64, coef_const_raw[1])
        )
        config["coefConstructibilidad"] = safe_expression_eval(coef_const_raw, variable_map)
    end
    
    config["max_constructibilidad"] = config["superficieTerreno"] * config["coefConstructibilidad"]
    
    # Calculate max losa based on building type and variant
    base_constructibilidad = config["max_constructibilidad"]
    is_apartment_special = (config["tipo_edificio"] == "departamento" && 
                           (config["flag_dfl2"] || config["flag_economica"]))
    
    config["max_losa_snt"] = if is_apartment_special
        base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR + COMMON_AREAS_FACTOR)
    else
        base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR)
    end
    
    # Floor configuration
    maxPisos = dict_requerimientos["n_pisos"]
    config["maxPisos"] = maxPisos
    config["default_min_pisos"] = max(MIN_FLOORS, maxPisos - DEFAULT_FLOOR_BUFFER)
    config["vec_pisos"] = collect(config["default_min_pisos"]:maxPisos)
    
    return config
end

"""
    calculate_density_limits(dict_requerimientos, config)

Calculates density limits and maximum apartments.
"""
function calculate_density_limits(dict_requerimientos, config)
    density_config = Dict{String, Any}()
    
    # Density calculation
    flagDensidadBruta = haskey(dict_requerimientos, "densidad_maxima_bruta")
    density_config["flagDensidadBruta"] = flagDensidadBruta
    
    superficie_densidad = flagDensidadBruta ? config["superficieTerrenoBruto"] : config["superficieTerreno"]
    max_densidad = flagDensidadBruta ? dict_requerimientos["densidad_maxima_bruta"] : dict_requerimientos["densidad_maxima_neta"]
    
    density_config["max_deptos"] = floor(max_densidad / DENSITY_DIVISOR * superficie_densidad / AREA_CONVERSION)
    
    # Ground occupation
    sup_patio_vivienda_economica = config["flag_economica"] ? dict_requerimientos["superficice_min_patio_x_depto"] : 0
    ocupacion_suelo = dict_requerimientos["coeficiente_de_ocupacion_de_suelo"]
    
    density_config["sup_patio_vivienda_economica"] = sup_patio_vivienda_economica
    density_config["max_ocupacion_suelo"] = if config["flag_economica"]
        config["superficieTerreno"] - density_config["max_deptos"] * sup_patio_vivienda_economica
    else
        config["superficieTerreno"] * ocupacion_suelo
    end
    
    return density_config
end

"""
    calculate_parking_requirements(dict_requerimientos, cabida_data)

Calculates all parking-related requirements with proper error handling.
"""
function calculate_parking_requirements(dict_requerimientos, cabida_data)
    parking = Dict{String, Any}()
    
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
        
        dict_estacionamientos = safe_expression_eval(dict_requerimientos["estacionamientos_autos"], car_parking_vars)
        parking["estacionamientos_autos_oficina"] = Float64(dict_estacionamientos["estacionamientos_autos_oficina"])
        parking["estacionamientos_autos_vivienda"] = Float64(dict_estacionamientos["estacionamientos_autos_vivienda"])
        parking["estacionamientos_autos_comercio"] = Float64(dict_estacionamientos["estacionamientos_autos_comercio"])
        parking["estacionamientos_autos"] = parking["estacionamientos_autos_oficina"] + 
                                          parking["estacionamientos_autos_vivienda"] + 
                                          parking["estacionamientos_autos_comercio"]
        
        # Visitor parking
        visitor_vars = Dict("estacionamientos_autos_vivienda" => parking["estacionamientos_autos_vivienda"])
        parking["estacionamientos_visitas"] = Float64(safe_expression_eval(dict_requerimientos["estacionamientos_visitas"], visitor_vars))
        
        # Total parking spots
        numEst = parking["estacionamientos_autos"] + parking["estacionamientos_visitas"]
        
        # Disabled parking
        disabled_vars = Dict("estacionamientos_autos" => numEst)
        parking["estacionamientos_discapacitados"] = Float64(safe_expression_eval(dict_requerimientos["estacionamientos_discapacitados"], disabled_vars))
        
        # Bicycle parking
        bike_vars = Dict(
            "estacionamientos_autos" => parking["estacionamientos_autos"],
            "estacionamientos_visitas" => parking["estacionamientos_visitas"],
            "carga_ocupacion" => DEFAULT_OCCUPATION_LOAD
        )
        parking["estacionamientos_bicicletas"] = Float64(safe_expression_eval(dict_requerimientos["estacionamientos_bicicletas"], bike_vars))
        
        # Metro discount
        metro_vars = Dict(
            "estacionamientos_autos_vivienda" => parking["estacionamientos_autos_vivienda"],
            "estacionamientos_autos_comercio" => parking["estacionamientos_autos_comercio"],
            "estacionamientos_autos_oficina" => parking["estacionamientos_autos_oficina"],
            "distancia_al_metro" => DEFAULT_METRO_DISTANCE
        )
        parking["descuento_estacionamientos_x_metro"] = Float64(safe_expression_eval(dict_requerimientos["descuento_estacionamientos_x_metro"], metro_vars))
        
        # Bicycle discount
        bike_discount_vars = Dict(
            "estacionamientos_autos" => parking["estacionamientos_autos"],
            "estacionamientos_visitas" => parking["estacionamientos_visitas"],
            "descuento_estacionamientos_x_metro" => parking["descuento_estacionamientos_x_metro"],
            "estacionamientos_bicicletas" => parking["estacionamientos_bicicletas"]
        )
        
        dict_descuento_bici = safe_expression_eval(dict_requerimientos["descuento_estacionamientos_x_bici"], bike_discount_vars)
        parking["descuento_estacionamientos_x_bici_t1"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici_t1"])
        parking["descuento_estacionamientos_x_bici_t2"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici_t2"])
        parking["descuento_estacionamientos_x_bici"] = Float64(dict_descuento_bici["descuento_estacionamientos_x_bici"])
        
        # Bicycle increase from discount
        bike_increase_vars = Dict("descuento_estacionamientos_x_bici_t2" => parking["descuento_estacionamientos_x_bici_t2"])
        parking["aumento_bici_x_descuento_estacionamientos"] = safe_expression_eval(dict_requerimientos["aumento_bici_x_descuento_estacionamientos"], bike_increase_vars)
        
        # Final calculations
        parking["estacionamientos_autos_final"] = parking["estacionamientos_autos"] + parking["estacionamientos_visitas"] - 
                                                 parking["descuento_estacionamientos_x_metro"] - parking["descuento_estacionamientos_x_bici"]
        parking["estacionamientos_bicicletas_final"] = parking["estacionamientos_bicicletas"] + parking["aumento_bici_x_descuento_estacionamientos"]
        
        return parking
        
    catch e
        @warn "Error calculating parking requirements: $e"
        # Return minimal parking configuration
        return Dict{String, Any}(
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
end

"""
    calculate_cabida_data(config, vec_ps_opt, vec_np_opt, dict_edificio_deptos)

Calculates capacity data for different building types.
"""
function calculate_cabida_data(config, vec_ps_opt, vec_np_opt, dict_edificio_deptos, dict_arquitectura)
    cabida = Dict{String, String}()
    
    if config["tipo_edificio"] == "departamento"
        cabida["cabida_sup_deptos"] = string(get(dict_arquitectura, "vecSupUtil", "0"))
        cabida["cabida_num_deptos"] = string(dict_edificio_deptos["numDeptosTipo"])
        cabida["cabida_sup_comercio"] = "0"
        cabida["cabida_num_comercio"] = "0"
        cabida["cabida_sup_oficinas"] = "0"
        cabida["cabida_num_oficinas"] = "0"
    else
        # Safely calculate area, handling empty polygons
        area_edif = 0.0
        for i in eachindex(vec_ps_opt)
            if !isempty(vec_ps_opt[i].Vertices)
                area_edif += polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i]
            end
        end
        cabida["cabida_sup_deptos"] = "0"
        cabida["cabida_num_deptos"] = "0"
        cabida["cabida_sup_comercio"] = "0"
        cabida["cabida_num_comercio"] = "0"
        cabida["cabida_sup_oficinas"] = string(OFFICE_AREA_PER_UNIT)
        cabida["cabida_num_oficinas"] = string(ceil(area_edif / OFFICE_AREA_PER_UNIT))
    end
    
    return cabida
end

"""
    calculate_underground_area(dict_geom, dict_requerimientos, dict_arquitectura, parking_data)

Calculates underground parking area requirements.
"""
function calculate_underground_area(dict_geom, dict_requerimientos, dict_arquitectura, parking_data)
    # Calculate required area
    supPorEstacionamiento = dict_arquitectura["supPorEstacionamiento"]
    supPorBodega = dict_arquitectura["supPorBodega"]
    supPorBicicleta = dict_arquitectura["supPorBicicleta"]
    
    # Calculate number of storage units
    numBodegas = if dict_arquitectura["tipo_edificio"] == "departamento"
        # This needs dict_edificio_deptos which is calculated later
        0  # Will be updated in main function
    else
        ceil(BODEGA_RATIO * (parking_data["estacionamientos_autos_final"] + parking_data["estacionamientos_visitas"]))
    end
    
    areaReq = parking_data["estacionamientos_autos_final"] * supPorEstacionamiento + 
              parking_data["estacionamientos_bicicletas_final"] * supPorBicicleta + 
              numBodegas * supPorBodega
    
    # Create underground area polygon
    vecSecTodos = dict_geom["vecSecTodos"]
    vecSecSinCalle = dict_geom["vecSecSinCalle"]
    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -dict_requerimientos["subterraneo_antejardin"]
    vec_dist[vecSecSinCalle] .= -dict_requerimientos["subterraneo_distanciamiento"]
    
    ps_predio = deepcopy(dict_geom["ps_predio"])
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)
    
    return areaReq, ps_areaEst, numBodegas
end

"""
    compile_results(config, density_config, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte, 
                   vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra,
                   cabida_data, parking_data, dict_edificio_deptos, max_sol, numBodegas)

Compiles final results dictionary.
"""
function compile_results(config, density_config, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte,
                        vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra,
                        cabida_data, parking_data, dict_edificio_deptos, max_sol, numBodegas, dict_arquitectura)
    
    return OrderedDict(
        "tipo_edificio" => config["tipo_edificio"],
        "variante_normativa" => config["variante_str"],
        "flag_sombra" => dict_arquitectura["flag_sombra"],
        "sup_edificada_snt" => max_sol,
        "vec_ps_opt" => vec_ps_opt,
        "vec_np_opt" => vec_np_opt,
        "vec_ps_subte" => vec_ps_subte,
        "vec_np_subte" => vec_np_subte,
        "vec_psVolteor" => vec_psVolteor,
        "vec_altVolteor" => vec_altVolteor,
        "vec_psVolConSombra" => vec_psVolConSombra,
        "vec_altVolConSombra" => vec_altVolConSombra,
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
        "dict_edificio_deptos" => config["tipo_edificio"] == "departamento" ? dict_edificio_deptos : 0
    )
end

"""
    compile_normative_comparison(config, density_config, vec_ps_opt, vec_np_opt, cabida_data, dict_edificio_deptos, dict_requerimientos)

Compiles project vs normative comparison dictionary.
"""
function compile_normative_comparison(config, density_config, vec_ps_opt, vec_np_opt, cabida_data, dict_edificio_deptos, dict_requerimientos)
    return OrderedDict(
        "densidad_proyecto" => sum(eval(Meta.parse(cabida_data["cabida_num_deptos"]))),
        "densidad_normativa" => density_config["max_deptos"],
        "losa_proyecto" => sum(isempty(vec_ps_opt[i].Vertices) ? 0.0 : polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "losa_normativa" => config["flag_economica"] ? LARGE_NUMBER : config["max_losa_snt"],
        "constructibilidad_proyecto" => dict_edificio_deptos["supUtil"],
        "constructibilidad_normativa" => config["flag_economica"] ? LARGE_NUMBER : config["max_constructibilidad"],
        "ocupacion_suelo_proyecto" => isempty(vec_ps_opt) || isempty(vec_ps_opt[1].Vertices) ? 0.0 : polyShape.polyArea(vec_ps_opt[1]),
        "ocupacion_suelo_normativa" => if config["flag_economica"]
            config["superficieTerreno"] - sum(eval(Meta.parse(cabida_data["cabida_num_deptos"]))) * density_config["sup_patio_vivienda_economica"]
        else
            density_config["max_ocupacion_suelo"]
        end,
        "pisos_proyecto" => sum(vec_np_opt[i] for i in eachindex(vec_ps_opt)),
        "pisos_normativa" => dict_requerimientos["n_pisos"],
        "supNoUtilizada" => dict_edificio_deptos["supNoUtilizada"]
    )
end

function opti_edificio(dict_geom, dict_arquitectura, dict_requerimientos)
    # Input validation
    validate_opti_edificio_inputs(dict_geom, dict_arquitectura, dict_requerimientos)
    
    # Calculate building configuration
    config = calculate_building_config(dict_geom, dict_arquitectura, dict_requerimientos)
    density_config = calculate_density_limits(dict_requerimientos, config)
    
    # Perform volume optimization
    vec_ps_opt, vec_np_opt, max_sol, vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra = opti_edificio_vol(
        dict_geom, dict_arquitectura, dict_requerimientos, config["vec_pisos"], 
        density_config["max_ocupacion_suelo"], config["max_losa_snt"]
    )
    
    # Validate optimization results
    if isempty(vec_ps_opt) || any(isempty(ps.Vertices) for ps in vec_ps_opt)
        @warn "Volume optimization returned empty polygons, using fallback solution"
        # Return minimal valid result
        return (
            OrderedDict(
                "tipo_edificio" => config["tipo_edificio"],
                "variante_normativa" => config["variante_str"],
                "flag_sombra" => dict_arquitectura["flag_sombra"],
                "sup_edificada_snt" => 0.0,
                "vec_ps_opt" => [PolyShape([], 1)],
                "vec_np_opt" => [0],
                "vec_ps_subte" => [PolyShape([], 1)],
                "vec_np_subte" => [0],
                "vec_psVolteor" => vec_psVolteor,
                "vec_altVolteor" => vec_altVolteor,
                "vec_psVolConSombra" => vec_psVolConSombra,
                "vec_altVolConSombra" => vec_altVolConSombra,
                "cabida_sup_deptos" => "0",
                "cabida_num_deptos" => "0",
                "cabida_sup_comercio" => "0",
                "cabida_num_comercio" => "0",
                "cabida_sup_oficinas" => "0",
                "cabida_num_oficinas" => "0"
            ),
            OrderedDict(
                "densidad_proyecto" => 0,
                "densidad_normativa" => density_config["max_deptos"],
                "losa_proyecto" => 0.0,
                "losa_normativa" => config["max_losa_snt"],
                "constructibilidad_proyecto" => 0.0,
                "constructibilidad_normativa" => config["max_constructibilidad"],
                "ocupacion_suelo_proyecto" => 0.0,
                "ocupacion_suelo_normativa" => density_config["max_ocupacion_suelo"],
                "pisos_proyecto" => 0,
                "pisos_normativa" => dict_requerimientos["n_pisos"],
                "supNoUtilizada" => 0.0
            )
        )
    end
    
    # Calculate apartment details if building type is apartment
    dict_edificio_deptos = if config["tipo_edificio"] == "departamento"
        opti_edificio_deptos(dict_arquitectura, config["max_constructibilidad"], density_config["max_deptos"], 
                           vec_ps_opt, vec_np_opt, config["flag_dfl2"], 
                           density_config["sup_patio_vivienda_economica"], config["superficieTerreno"])
    else
        Dict{String, Any}("numDeptosTipo" => [0], "supUtil" => 0.0, "supNoUtilizada" => 0.0)
    end
    
    # Calculate capacity data
    cabida_data = calculate_cabida_data(config, vec_ps_opt, vec_np_opt, dict_edificio_deptos, dict_arquitectura)
    
    # Calculate parking requirements
    parking_data = calculate_parking_requirements(dict_requerimientos, cabida_data)
    
    # Calculate storage units for apartments
    numBodegas = if config["tipo_edificio"] == "departamento"
        sum(dict_edificio_deptos["numDeptosTipo"])
    else
        ceil(BODEGA_RATIO * (parking_data["estacionamientos_autos_final"] + parking_data["estacionamientos_visitas"]))
    end
    
    # Calculate underground area requirements
    areaReq, ps_areaEst, _ = calculate_underground_area(dict_geom, dict_requerimientos, dict_arquitectura, parking_data)
    
    # Update area requirement with correct bodega count
    supPorEstacionamiento = dict_arquitectura["supPorEstacionamiento"]
    supPorBodega = dict_arquitectura["supPorBodega"]
    supPorBicicleta = dict_arquitectura["supPorBicicleta"]
    
    areaReq = parking_data["estacionamientos_autos_final"] * supPorEstacionamiento + 
              parking_data["estacionamientos_bicicletas_final"] * supPorBicicleta + 
              numBodegas * supPorBodega
    
    # Optimize underground parking volume
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(dict_geom["ps_predio"], ps_areaEst, COEF_OCUPACION_EST, areaReq)
    
    # Compile results
    dict_resultados = compile_results(config, density_config, vec_ps_opt, vec_np_opt, vec_ps_subte, vec_np_subte,
                                     vec_psVolteor, vec_altVolteor, vec_psVolConSombra, vec_altVolConSombra,
                                     cabida_data, parking_data, dict_edificio_deptos, max_sol, numBodegas, dict_arquitectura)
    
    dict_proyecto_vs_normativa = compile_normative_comparison(config, density_config, vec_ps_opt, vec_np_opt, 
                                                             cabida_data, dict_edificio_deptos, dict_requerimientos)

    return dict_resultados, dict_proyecto_vs_normativa
end