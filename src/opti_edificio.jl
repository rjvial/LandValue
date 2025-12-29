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
const LARGE_NUMBER = 999999.0


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

function estimacion_ocupacion_suelo_viv_econ(superficieTerreno, max_deptos, sup_patio_vivienda_economica, coefSupComun,
                                    vecSupInterior, vecSupTerraza, vecSupUtil)
    
    sup_depto_promedio = (sum(vecSupInterior.*(vecSupUtil .<= 140)) + sum(vecSupTerraza.*(vecSupUtil .<= 140)) + sum(vecSupUtil.*(vecSupUtil .<= 140)) * coefSupComun) /
                            length(vecSupInterior)
    num_pisos = 4
    num_deptos_actual = floor(max_deptos ÷ 2)

    while true
        sup_ocupacion_est = superficieTerreno - num_deptos_actual * sup_patio_vivienda_economica

        if sup_ocupacion_est <= 0
            break
        end

        sup_edif_snt = sup_ocupacion_est * num_pisos
        num_deptos_estimado = floor(Int, sup_edif_snt / sup_depto_promedio)

        if num_deptos_actual < num_deptos_estimado
            num_deptos_actual = num_deptos_actual + 1
        else
            break
        end

        if num_deptos_actual > max_deptos
            num_deptos_actual = max_deptos
            break
        end
    end

    num_deptos_opt = min(num_deptos_actual, max_deptos)
    sup_ocupacion_est = superficieTerreno - num_deptos_opt * sup_patio_vivienda_economica
    
    return sup_ocupacion_est
end

function opti_edificio(dict_geom, dict_arquitectura, dict_normativa_raw, id_opti=nothing, id_combi=nothing)
    # ============================================================================
    # MAIN BUILDING OPTIMIZATION FUNCTION
    # ============================================================================

    profundidad_pasillo = 1.5 # opti_floor_plan
    min_ancho_pasillo = 4.0 # opti_floor_plan
    max_ancho_terraza = 4.0 # opti_floor_plan

    dict_normativa = OrderedDict(
        "id_combi" => id_combi,
        "tipo_edificio" => dict_arquitectura["arq_tipo_edificio"],
        "variante_normativa" => dict_arquitectura["arq_variante_normativa"],
        "flag_dfl2" => dict_arquitectura["arq_variante_normativa"] == "dfl_2",
        "flag_economica" => dict_arquitectura["arq_variante_normativa"] == "vivienda_economica",
        "flag_fusion" => dict_geom["n_predios"] >= 2,
        "flag_sombra" => dict_arquitectura["arq_flag_sombra"],
        "flag_vano" => dict_arquitectura["arq_flag_vano"],
        "flag_densidad_bruta" => haskey(dict_normativa_raw, "norm_densidad_maxima_bruta")
    )

    for (key, value) in dict_normativa_raw
        if isa(value, Number)
            dict_normativa[key] = value
        end
    end

    # ============================================================================
    # 1. BUILDING CONFIGURATION SETUP
    # ============================================================================    
    # Constructibility calculation
    coef_const_raw = dict_normativa_raw["norm_coeficiente_de_constructibilidad"]
    if isa(coef_const_raw, Number)
        coefConstructibilidad = coef_const_raw
    elseif typeof(coef_const_raw[1]) == Float64
        coefConstructibilidad = coef_const_raw[1]
    else
        variable_map = Dict(
            "n_predios" => dict_geom["n_predios"],
            "coeficiente_de_constructibilidad" => parse(Float64, coef_const_raw[1])
        )
        coefConstructibilidad = python_expression_eval_with_varmap(coef_const_raw, variable_map)
    end
    
    base_constructibilidad = dict_geom["sup_terreno_sii"] * coefConstructibilidad

    dict_normativa["norm_max_constructibilidad"] = base_constructibilidad

    # Calculate max losa based on building type and variant
    is_apartment_special = (dict_normativa["tipo_edificio"] == "departamento" &&
                           (dict_normativa["flag_dfl2"] || dict_normativa["flag_economica"]))
    if is_apartment_special
        max_losa_snt = base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR + COMMON_AREAS_FACTOR)
    else
        max_losa_snt = base_constructibilidad * (INTERIOR_FACTOR + TERRACE_FACTOR)
    end


    # ============================================================================
    # 2. DENSITY AND OCCUPATION CALCULATIONS
    # ============================================================================
    # Density calculation
    flagDensidadBruta = dict_normativa["flag_densidad_bruta"]

    superficie_densidad = flagDensidadBruta ? dict_geom["sup_terreno_bruto"] : dict_geom["sup_terreno_sii"]
    max_densidad = flagDensidadBruta ? dict_normativa_raw["norm_densidad_maxima_bruta"] : dict_normativa_raw["norm_densidad_maxima_neta"]
    
    dict_normativa["norm_max_unidades"] = floor(max_densidad / DENSITY_DIVISOR * superficie_densidad / AREA_CONVERSION)

    # Ground occupation
    sup_patio_vivienda_economica = dict_normativa["flag_economica"] ? dict_normativa_raw["norm_superficice_min_patio_x_depto"] : 0    
    if dict_normativa["flag_economica"]
        superficieTerreno = dict_geom["sup_terreno_sii"]
        max_deptos = dict_normativa["norm_max_unidades"]
        coefSupComun = dict_arquitectura["arq_coefSupComun"]
        vecSupInterior = dict_arquitectura["arq_vecSupInterior"]
        vecSupTerraza = dict_arquitectura["arq_vecSupTerraza"]
        vecSupUtil = dict_arquitectura["arq_vecSupUtil"]
        dict_normativa["norm_max_ocupacion_suelo"] = estimacion_ocupacion_suelo_viv_econ(superficieTerreno, max_deptos, sup_patio_vivienda_economica, coefSupComun,
                                            vecSupInterior, vecSupTerraza, vecSupUtil)
    else
        ocupacion_suelo = dict_normativa_raw["norm_coeficiente_de_ocupacion_de_suelo"]
        dict_normativa["norm_max_ocupacion_suelo"] = dict_geom["sup_terreno_sii"] * ocupacion_suelo
    end


    # ============================================================================
    # 3. VOLUME OPTIMIZATION
    # ============================================================================
    # Floor configuration
    maxPisos = get(dict_normativa_raw, "norm_n_pisos", 9999)
    default_min_pisos = max(MIN_FLOORS, maxPisos - DEFAULT_FLOOR_BUFFER)
    vec_pisos = collect(default_min_pisos:maxPisos)

    max_ocupacion_suelo = dict_normativa["norm_max_ocupacion_suelo"]
    
    # Optimiza el volumen del edificio en base a: distanciamiento, antejardín, altura_max, rasante, max_losa_snt,
    # volumen teórico, ocupación de suelo, crujía (max_constructibilidad se consider a través de max_losa_snt)
    
    result_vol = opti_edificio_vol(dict_geom, dict_arquitectura, dict_normativa_raw, vec_pisos, max_ocupacion_suelo, max_losa_snt)

    ps_opt = result_vol["ps_opt"]
    np_opt = result_vol["np_opt"]
    max_sol = result_vol["max_sol"]
    vec_psVolteor = result_vol["vec_psVolteor"]
    vec_altVolteor = result_vol["vec_altVolteor"]
    vec_psVolConSombra = result_vol["vec_psVolConSombra"]
    vec_altVolConSombra = result_vol["vec_altVolConSombra"]
    ps_sombraEdif_p = result_vol["ps_sombraEdif_p"]
    ps_sombraEdif_o = result_vol["ps_sombraEdif_o"]
    ps_sombraEdif_s = result_vol["ps_sombraEdif_s"]
    ps_sombraVolTeorico_p = result_vol["ps_sombraVolTeorico_p"]
    ps_sombraVolTeorico_o = result_vol["ps_sombraVolTeorico_o"]
    ps_sombraVolTeorico_s = result_vol["ps_sombraVolTeorico_s"]

    # distaciamiento y antejardín
    dict_normativa["norm_antejardin"] = dict_normativa_raw["norm_antejardin"]

    n_pisos_opt = np_opt
    distanciamiento = dict_normativa_raw["norm_distanciamiento"][1]
    expr_str = expression_converter.parse_python_expression(dict_normativa_raw["norm_distanciamiento"][3])
    expr_str = replace(expr_str, "flag_sombra" => false)
    expr_str = replace(expr_str, "altura" => string(n_pisos_opt*dict_arquitectura["arq_alturaPiso"]))
    expr_str = replace(expr_str, "n_pisos" => string(n_pisos_opt))
    expr_str = replace(expr_str, "distanciamiento" => string(distanciamiento))
    expr_str = replace(expr_str, "flag_vano" => string(dict_arquitectura["arq_flag_vano"]))
    dict_normativa["norm_distanciamiento"] = eval(Meta.parse(expr_str))


    # ============================================================================
    # 4. APARTMENT SIZE CONFIGURATION
    # ============================================================================
    max_constructibilidad = dict_normativa["norm_max_constructibilidad"]
    max_deptos = dict_normativa["norm_max_unidades"]

    dict_edificio_deptos = opti_planta_edificio(dict_arquitectura, max_constructibilidad, max_deptos, ps_opt, np_opt)

    # ============================================================================
    # 5. APARTMENT SHAPE COMPILATION
    # ============================================================================
    num_pisos = Int(np_opt)
    num_pisos_superiores = num_pisos - 1

    results = opti_floor_plan(dict_edificio_deptos, max_constructibilidad, num_pisos_superiores,
                profundidad_pasillo=profundidad_pasillo,
                min_ancho_pasillo=min_ancho_pasillo)

    results_pisos_superiores = results["pisos_superiores"]
    results_primer_piso = results["primer_piso"]

    sup_interior_pisos_superiores = sum([polyShape.polyArea(ps) for ps in results_pisos_superiores["vec_ps_deptos_interior_all"]]; init=0.0)
    sup_terraza_pisos_superiores = sum([polyShape.polyArea(ps) for ps in results_pisos_superiores["vec_ps_terrazas_all"] if polyShape.polyArea(ps) > 0.0]; init=0.0)
    sup_comun_pisos_superiores = polyShape.polyArea(results_pisos_superiores["ps_area_comun_total"])

    if !isnothing(results_primer_piso)
        sup_interior_primer_piso = sum([polyShape.polyArea(ps) for ps in results_primer_piso["vec_ps_deptos_interior_all"]]; init=0.0)
        sup_terraza_primer_piso = sum([polyShape.polyArea(ps) for ps in results_primer_piso["vec_ps_terrazas_all"] if polyShape.polyArea(ps) > 0.0]; init=0.0)
        sup_comun_primer_piso = polyShape.polyArea(results_primer_piso["ps_area_comun_total"])
    else
        sup_interior_primer_piso = 0.0
        sup_terraza_primer_piso = 0.0
        sup_comun_primer_piso = 0.0
    end

    sup_interior_edificio = sup_interior_pisos_superiores * num_pisos_superiores + sup_interior_primer_piso
    sup_terraza_edificio = sup_terraza_pisos_superiores * num_pisos_superiores + sup_terraza_primer_piso
    sup_comun_edificio = sup_comun_pisos_superiores * num_pisos_superiores + sup_comun_primer_piso

    num_deptos_edificio = length(results_pisos_superiores["vec_ps_deptos_interior_all"]) * num_pisos_superiores
    if !isnothing(results_primer_piso)
        num_deptos_edificio += length(results_primer_piso["vec_ps_deptos_interior_all"])
    end

    W = dict_edificio_deptos["W"]
    H = dict_edificio_deptos["H"]
    sup_no_utilizada_edificio = W * H * num_pisos - sup_interior_edificio - sup_comun_edificio - sup_terraza_edificio

    # ============================================================================
    # 6. CAPACITY DATA CALCULATION
    # ============================================================================
    cabida_data = Dict{String, Any}()
    if dict_normativa["tipo_edificio"] == "departamento"
        vec_areas_pisos_superiores = [polyShape.polyArea(ps) for ps in results_pisos_superiores["vec_ps_deptos_interior_all"]]
        vec_areas_primer_piso = !isnothing(results_primer_piso) ? [polyShape.polyArea(ps) for ps in results_primer_piso["vec_ps_deptos_interior_all"]] : Float64[]

        all_areas = vcat(vec_areas_pisos_superiores, vec_areas_primer_piso)
        num_pisos_sup = length(vec_areas_pisos_superiores)

        area_dict = Dict{Float64, Vector{Int}}()
        for (idx, area) in enumerate(all_areas)
            if !haskey(area_dict, area)
                area_dict[area] = Int[]
            end
            push!(area_dict[area], idx)
        end

        vec_sup_deptos = Float64[]
        vec_num_deptos = Int[]
        vec_num_deptos_primerPiso = Int[]
        vec_num_deptos_pisosSup = Int[]

        for (area, indices) in sort(collect(area_dict), by=x->x[1])
            push!(vec_sup_deptos, area)

            count_primer = count(idx -> idx > num_pisos_sup, indices)
            count_superior = count(idx -> idx <= num_pisos_sup, indices)

            push!(vec_num_deptos_primerPiso, count_primer)
            push!(vec_num_deptos_pisosSup, count_superior)
            push!(vec_num_deptos, count_primer + count_superior * (num_pisos - 1))
        end

        cabida_data["vec_sup_deptos"] = vec_sup_deptos
        cabida_data["vec_num_deptos"] = vec_num_deptos
        cabida_data["vec_num_deptos_primerPiso"] = vec_num_deptos_primerPiso
        cabida_data["vec_num_deptos_pisosSup"] = vec_num_deptos_pisosSup
        cabida_data["vec_sup_comercio"] = 0
        cabida_data["vec_num_comercio"] = 0
        cabida_data["vec_sup_oficinas"] = 0
        cabida_data["vec_num_oficinas"] = 0
    else
        # Safely calculate area, handling empty polygons
        area_edif = 0.0
        if !isempty(ps_opt.Vertices)
            area_edif = polyShape.polyArea(ps_opt) * np_opt
        end
        cabida_data["vec_sup_deptos"] = 0
        cabida_data["vec_num_deptos"] = 0
        cabida_data["vec_num_deptos_primerPiso"] = 0
        cabida_data["vec_num_deptos_pisosSup"] = 0
        cabida_data["vec_sup_comercio"] = 0
        cabida_data["vec_num_comercio"] = 0
        cabida_data["vec_sup_oficinas"] = OFFICE_AREA_PER_UNIT
        cabida_data["vec_num_oficinas"] = Int(ceil(area_edif / OFFICE_AREA_PER_UNIT))
    end

    # ============================================================================
    # 7. PARKING REQUIREMENTS CALCULATION
    # ============================================================================
    car_parking_vars = Dict(
        "vec_sup_deptos" => cabida_data["vec_sup_deptos"],
        "vec_num_deptos" => cabida_data["vec_num_deptos"],
        "vec_sup_comercio" => cabida_data["vec_sup_comercio"],
        "vec_num_comercio" => cabida_data["vec_num_comercio"],
        "vec_sup_oficinas" => cabida_data["vec_sup_oficinas"],
        "vec_num_oficinas" => cabida_data["vec_num_oficinas"],
        "cabida_sup_deptos" => cabida_data["vec_sup_deptos"],
        "cabida_num_deptos" => sum(cabida_data["vec_num_deptos"]),
        "cabida_sup_comercio" => cabida_data["vec_sup_comercio"],
        "cabida_num_comercio" => sum(cabida_data["vec_num_comercio"]),
        "cabida_sup_oficinas" => cabida_data["vec_sup_oficinas"],
        "cabida_num_oficinas" => sum(cabida_data["vec_num_oficinas"])
    )
    
    dict_estacionamientos = python_expression_eval_with_varmap(dict_normativa_raw["norm_estacionamientos_autos"], car_parking_vars)
    dict_normativa["norm_estacionamientos_autos_oficina"] = Int(dict_estacionamientos["estacionamientos_autos_oficina"])
    dict_normativa["norm_estacionamientos_autos_vivienda"] = Int(dict_estacionamientos["estacionamientos_autos_vivienda"])
    dict_normativa["norm_estacionamientos_autos_comercio"] = Int(dict_estacionamientos["estacionamientos_autos_comercio"])
    dict_normativa["norm_estacionamientos_vendibles"] = dict_normativa["norm_estacionamientos_autos_oficina"] + 
                                                                dict_normativa["norm_estacionamientos_autos_vivienda"] +
                                                                dict_normativa["norm_estacionamientos_autos_comercio"]

    # Visitor parking
    visitor_vars = Dict("estacionamientos_autos_vivienda" => dict_normativa["norm_estacionamientos_autos_vivienda"])
    dict_normativa["norm_estacionamientos_visitas"] = Int(python_expression_eval_with_varmap(dict_normativa_raw["norm_estacionamientos_visitas"], visitor_vars))
    
    # Disabled parking
    disabled_vars = Dict("estacionamientos_autos" => dict_normativa["norm_estacionamientos_vendibles"] + dict_normativa["norm_estacionamientos_visitas"])
    dict_normativa["norm_estacionamientos_discapacitados"] = Int(python_expression_eval_with_varmap(dict_normativa_raw["norm_estacionamientos_discapacitados"], disabled_vars))

    # Bicycle parking
    bike_vars = Dict(
        "estacionamientos_autos" => dict_normativa["norm_estacionamientos_vendibles"],
        "estacionamientos_visitas" => dict_normativa["norm_estacionamientos_visitas"],
        "carga_ocupacion" => DEFAULT_OCCUPATION_LOAD
    )
    dict_normativa["norm_estacionamientos_bicicletas"] = Int(python_expression_eval_with_varmap(dict_normativa_raw["norm_estacionamientos_bicicletas"], bike_vars))
    
    # Metro discount
    metro_vars = Dict(
        "estacionamientos_autos_vivienda" => dict_normativa["norm_estacionamientos_autos_vivienda"],
        "estacionamientos_autos_comercio" => dict_normativa["norm_estacionamientos_autos_comercio"],
        "estacionamientos_autos_oficina" => dict_normativa["norm_estacionamientos_autos_oficina"],
        "distancia_al_metro" => DEFAULT_METRO_DISTANCE
    )
    dict_normativa["norm_descuento_estacionamientos_x_metro"] = Int(python_expression_eval_with_varmap(dict_normativa_raw["norm_descuento_estacionamientos_x_metro"], metro_vars))

    # Bicycle discount
    bike_discount_vars = Dict(
        "estacionamientos_autos" => dict_normativa["norm_estacionamientos_vendibles"],
        "estacionamientos_visitas" => dict_normativa["norm_estacionamientos_visitas"],
        "descuento_estacionamientos_x_metro" => dict_normativa["norm_descuento_estacionamientos_x_metro"],
        "estacionamientos_bicicletas" => dict_normativa["norm_estacionamientos_bicicletas"]
    )
    dict_descuento_bici = python_expression_eval_with_varmap(dict_normativa_raw["norm_descuento_estacionamientos_x_bici"], bike_discount_vars)
    dict_normativa["norm_descuento_estacionamientos_x_bici_t1"] = Int(dict_descuento_bici["descuento_estacionamientos_x_bici_t1"])
    dict_normativa["norm_descuento_estacionamientos_x_bici_t2"] = Int(dict_descuento_bici["descuento_estacionamientos_x_bici_t2"])
    dict_normativa["norm_descuento_estacionamientos_x_bici"] = Int(dict_descuento_bici["descuento_estacionamientos_x_bici"])

    # Bicycle increase from discount
    bike_increase_vars = Dict("descuento_estacionamientos_x_bici_t2" => dict_normativa["norm_descuento_estacionamientos_x_bici_t2"])
    dict_normativa["norm_aumento_bici_x_descuento_estacionamientos"] = python_expression_eval_with_varmap(dict_normativa_raw["norm_aumento_bici_x_descuento_estacionamientos"], bike_increase_vars)

    # Final calculations
    dict_normativa["norm_estacionamientos_autos_con_descuentos"] = dict_normativa["norm_estacionamientos_vendibles"] + dict_normativa["norm_estacionamientos_visitas"] -
                                                dict_normativa["norm_descuento_estacionamientos_x_metro"] - dict_normativa["norm_descuento_estacionamientos_x_bici"]
    dict_normativa["norm_estacionamientos_bicicletas_con_incrementos"] = dict_normativa["norm_estacionamientos_bicicletas"] + dict_normativa["norm_aumento_bici_x_descuento_estacionamientos"]

    
    # ============================================================================
    # 8. STORAGE AND UNDERGROUND AREA CALCULATION
    # ============================================================================
    if dict_normativa["tipo_edificio"] == "departamento"
        numBodegas = sum(cabida_data["vec_num_deptos"])
    else
        numBodegas = ceil(BODEGA_RATIO * (dict_normativa["norm_estacionamientos_vendibles"]))
    end
    
    # Calculate underground area requirements
    supPorEstacionamiento = dict_arquitectura["arq_supPorEstacionamiento"]
    supPorBodega = dict_arquitectura["arq_supPorBodega"]
    supPorBicicleta = dict_arquitectura["arq_supPorBicicleta"]
    
    areaEst_requerida = Float64(dict_normativa["norm_estacionamientos_autos_con_descuentos"] * supPorEstacionamiento +
                            dict_normativa["norm_estacionamientos_bicicletas_con_incrementos"] * supPorBicicleta +
                            numBodegas * supPorBodega)

    # Create underground area polygon
    vecSecTodos = dict_geom["vecSecTodos"]
    vecSecSinCalle = dict_geom["vecSecSinCalle"]
    vec_dist = Float64.(copy(vecSecTodos))
    vec_dist .= -dict_normativa_raw["norm_subterraneo_antejardin"]
    vec_dist[vecSecSinCalle] .= -dict_normativa_raw["norm_subterraneo_distanciamiento"]
    
    ps_predio = deepcopy(dict_geom["ps_combi"])
    ps_areaEst = polyShape.partialPolyOffset(ps_predio, vecSecTodos, vec_dist)
    
    
    # ============================================================================
    # 9. UNDERGROUND VOLUME OPTIMIZATION
    # ============================================================================
    vec_ps_subte, vec_np_subte = opti_vol_estacionamiento(dict_geom["ps_combi"], ps_areaEst, COEF_OCUPACION_EST, areaEst_requerida)

    # ============================================================================
    # 10. RESULTS COMPILATION
    # ============================================================================
    dict_proyecto = OrderedDict(
        "proyecto_sup_edificada_snt" => max_sol,
        "proyecto_pisos_snt" => Int8(np_opt),
        "proyecto_sup_edificada_bnt" => areaEst_requerida,
        "proyecto_pisos_bnt" => Int8(sum(vec_np_subte[i] for i in eachindex(vec_ps_subte))),
        "proyecto_vec_sup_interior_deptos" => cabida_data["vec_sup_deptos"],
        "proyecto_vec_num_deptos" => cabida_data["vec_num_deptos"],
        "proyecto_vec_num_deptos_primerPiso" => cabida_data["vec_num_deptos_primerPiso"],
        "proyecto_vec_num_deptos_pisosSup" => cabida_data["vec_num_deptos_pisosSup"],
        "proyecto_vec_sup_comercio" => cabida_data["vec_sup_comercio"],
        "proyecto_vec_num_comercio" => cabida_data["vec_num_comercio"],
        "proyecto_vec_sup_oficinas" => cabida_data["vec_sup_oficinas"],
        "proyecto_vec_num_oficinas" => cabida_data["vec_num_oficinas"],
        "proyecto_estacionamientos_vendibles" => dict_normativa["norm_estacionamientos_autos_con_descuentos"] - dict_normativa["norm_estacionamientos_visitas"],
        "proyecto_estacionamientos_visitas" => dict_normativa["norm_estacionamientos_visitas"],
        "proyecto_estacionamientos_autos_con_descuentos" => dict_normativa["norm_estacionamientos_autos_con_descuentos"],
        "proyecto_estacionamientos_discapacitados" => dict_normativa["norm_estacionamientos_discapacitados"],
        "proyecto_estacionamientos_bicicletas_con_incrementos" => dict_normativa["norm_estacionamientos_bicicletas_con_incrementos"],
        "proyecto_bodegas" => Int8(numBodegas),
        "proyecto_supUtil" => sup_interior_edificio + 0.5 * sup_terraza_edificio,
        "proyecto_supUtilPrimerPiso" => sup_interior_primer_piso + 0.5 * sup_terraza_primer_piso,
        "proyecto_supUtilPisosSup" => sup_interior_pisos_superiores + 0.5 * sup_terraza_pisos_superiores,
        "proyecto_supComun" => sup_comun_edificio,
        "proyecto_supComunPrimerPiso" => sup_comun_primer_piso,
        "proyecto_supComunPisosSup" => sup_comun_pisos_superiores,
        "proyecto_supTerraza" => sup_terraza_edificio,
        "proyecto_supTerrazaPrimerPiso" => sup_terraza_primer_piso,
        "proyecto_supTerrazaPisosSup" => sup_terraza_pisos_superiores,
        "proyecto_supInterior" => sup_interior_edificio,
        "proyecto_supInteriorPrimerPiso" => sup_interior_primer_piso,
        "proyecto_supInteriorPisosSup" => sup_interior_pisos_superiores,
        "proyecto_descuento_dfl2" => 0.0,
        "proyecto_supNoUtilizada" => sup_no_utilizada_edificio,
        "proyecto_numDeptos" => Int(round(num_deptos_edificio)),
        "proyecto_ps_opt" => ps_opt,
        "proyecto_np_opt" => np_opt,
        "proyecto_vec_ps_subte" => vec_ps_subte,
        "proyecto_vec_np_subte" => vec_np_subte,
        "proyecto_vec_psVolteor" => vec_psVolteor,
        "proyecto_vec_altVolteor" => vec_altVolteor,
        "proyecto_vec_psVolConSombra" => vec_psVolConSombra,
        "proyecto_vec_altVolConSombra" => vec_altVolConSombra,
        "proyecto_ps_sombraEdif_p" => ps_sombraEdif_p,
        "proyecto_ps_sombraEdif_o" => ps_sombraEdif_o,
        "proyecto_ps_sombraEdif_s" => ps_sombraEdif_s,
        "proyecto_ps_sombraVolTeorico_p" => ps_sombraVolTeorico_p,
        "proyecto_ps_sombraVolTeorico_o" => ps_sombraVolTeorico_o,
        "proyecto_ps_sombraVolTeorico_s" => ps_sombraVolTeorico_s,
        "proyecto_num_unidades" => sum(cabida_data["vec_num_deptos"]),
        "proyecto_constructibilidad" => sup_interior_edificio + 0.5 * sup_terraza_edificio,
        "proyecto_ocupacion_suelo" => isempty(ps_opt.Vertices) ? 0.0 : polyShape.polyArea(ps_opt)
        )

    return dict_proyecto, dict_normativa, results_pisos_superiores, results_primer_piso
end