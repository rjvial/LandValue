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

function print_results(results::AbstractDict)

    W = results["W"]
    H = results["H"]

    println("\n" * "="^60)
    println("RESULTADOS OPTIMIZACIÓN ASIGNACIÓN DEPTOS")
    println("="^60)
    println("Estado: $(results["status"])")

    if isnothing(results["objective_value"])
        println("Valor objetivo: N/A (sin solución factible)")
    else
        println("Valor objetivo: $(round(results["objective_value"], digits=2))")
    end

    println("Tiempo de solución: $(round(results["solve_time"], digits=2)) segundos")

    if !isnothing(results["objective_value"])
        totals = get(results, "totals", nothing)
        num_pisos_sup = get(results, "num_pisos_superiores", 1)

        if !isnothing(totals)
            println("Total departamentos edificio: $(round(totals["deptos"]["edificio"], digits=0))")
            println("  - Primer piso: $(round(totals["deptos"]["primer_piso"], digits=0)) deptos")
            println("  - Pisos superiores: $(round(totals["deptos"]["pisos_superiores"], digits=0)) deptos/piso × $(num_pisos_sup) pisos = $(round(totals["deptos"]["pisos_superiores"] * num_pisos_sup, digits=0)) deptos")
        end
    else
        println("Total departamentos: 0")
    end

    if !isnothing(results["objective_value"])
        totals = get(results, "totals", nothing)

        if !isnothing(totals)
            area_interior_pp = totals["superficie_interior"]["primer_piso"]
            area_terraza_pp = totals["superficie_terraza"]["primer_piso"]
            area_pasillo_pp = totals["superficie_pasillo"]["primer_piso"]
            area_comun_pp = totals["superficie_comun"]["primer_piso"]
            area_util_pp = area_interior_pp + area_terraza_pp / 2

            area_interior_ps = totals["superficie_interior"]["pisos_superiores"]
            area_terraza_ps = totals["superficie_terraza"]["pisos_superiores"]
            area_pasillo_ps = totals["superficie_pasillo"]["pisos_superiores"]
            area_comun_ps = totals["superficie_comun"]["pisos_superiores"]
            area_util_ps = area_interior_ps + area_terraza_ps / 2
        else
            area_interior_pp = area_terraza_pp = area_pasillo_pp = area_comun_pp = area_util_pp = 0.0
            area_interior_ps = area_terraza_ps = area_pasillo_ps = area_comun_ps = area_util_ps = 0.0
        end

        num_pisos_sup = get(results, "num_pisos_superiores", 1)
        num_pisos_total = get(results, "num_pisos_total", 1)

        area_total_losa_pp = area_interior_pp + area_terraza_pp + area_comun_pp
        area_total_losa_ps = area_interior_ps + area_terraza_ps + area_comun_ps
        area_total_losa_edificio = area_total_losa_pp + area_total_losa_ps * num_pisos_sup

        println("\n" * "="^80)
        println("RESUMEN DE ÁREAS POR PISO")
        println("="^80)
        println("")

        W_building = W
        H_building = H
        area_emplazamiento_por_piso = W_building * H_building
        area_emplazamiento_total = area_emplazamiento_por_piso * num_pisos_total

        area_no_utilizada_pp = area_emplazamiento_por_piso - (area_interior_pp + area_terraza_pp + area_comun_pp)
        area_no_utilizada_ps = area_emplazamiento_por_piso - (area_interior_ps + area_terraza_ps + area_comun_ps)
        area_no_utilizada_total = area_no_utilizada_pp + area_no_utilizada_ps * num_pisos_sup

        deptos_dict = get(results, "deptos", Dict())

        area_nucleo_pp = 0.0
        area_nucleo_ps = 0.0
        for depto_data in values(deptos_dict)
            sup_nucleo = get(depto_data, "sup_nucleo", 0.0)
            area_nucleo_pp += depto_data["num_unidades_primer_piso"] * sup_nucleo
            area_nucleo_ps += depto_data["num_unidades_por_piso_superior"] * sup_nucleo
        end
        area_nucleo_total = area_nucleo_pp + area_nucleo_ps * num_pisos_sup

        println("┌─────────────────────┬──────────────────┬──────────────────┬──────────────────┐")
        println("│                     │  Primer Piso     │  Piso Superior   │  Total Edificio  │")
        println("│                     │    (1 piso)      │   (por piso)     │   ($(num_pisos_total) pisos)      │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Interior       │ $(lpad(round(area_interior_pp, digits=1), 12)) m² │ $(lpad(round(area_interior_ps, digits=1), 12)) m² │ $(lpad(round(area_interior_pp + area_interior_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Terraza        │ $(lpad(round(area_terraza_pp, digits=1), 12)) m² │ $(lpad(round(area_terraza_ps, digits=1), 12)) m² │ $(lpad(round(area_terraza_pp + area_terraza_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Común          │ $(lpad(round(area_comun_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps, digits=1), 12)) m² │ $(lpad(round(area_comun_pp + area_comun_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Área Pasillo    │ $(lpad(round(area_pasillo_pp, digits=1), 12)) m² │ $(lpad(round(area_pasillo_ps, digits=1), 12)) m² │ $(lpad(round(area_pasillo_pp + area_pasillo_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│   - Área Núcleo     │ $(lpad(round(area_nucleo_pp, digits=1), 12)) m² │ $(lpad(round(area_nucleo_ps, digits=1), 12)) m² │ $(lpad(round(area_nucleo_total, digits=1), 12)) m² │")
        println("│   - Otros espacios  │ $(lpad(round(area_comun_pp - area_pasillo_pp - area_nucleo_pp, digits=1), 12)) m² │ $(lpad(round(area_comun_ps - area_pasillo_ps - area_nucleo_ps, digits=1), 12)) m² │ $(lpad(round((area_comun_pp - area_pasillo_pp - area_nucleo_pp) + (area_comun_ps - area_pasillo_ps - area_nucleo_ps) * num_pisos_sup, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Losa SNT       │ $(lpad(round(area_total_losa_pp, digits=1), 12)) m² │ $(lpad(round(area_total_losa_ps, digits=1), 12)) m² │ $(lpad(round(area_total_losa_edificio, digits=1), 12)) m² │")
        println("│ Área No Utilizada   │ $(lpad(round(area_no_utilizada_pp, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_ps, digits=1), 12)) m² │ $(lpad(round(area_no_utilizada_total, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Emplazamiento  │ $(lpad(round(area_emplazamiento_por_piso, digits=1), 12)) m² │ $(lpad(round(area_emplazamiento_por_piso, digits=1), 12)) m² │ $(lpad(round(area_emplazamiento_total, digits=1), 12)) m² │")
        println("│ (W × Profundidad)   │                  │                  │                  │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Útil           │ $(lpad(round(area_util_pp, digits=1), 12)) m² │ $(lpad(round(area_util_ps, digits=1), 12)) m² │ $(lpad(round(area_util_pp + area_util_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ (Interior + Terr/2) │                  │                  │                  │")
        println("└─────────────────────┴──────────────────┴──────────────────┴──────────────────┘")
        println("")
        println("Notas:")
        println("  • Área Losa SNT = Área Interior + Área Terraza + Área Común")
        println("  • Área Emplazamiento = Área Losa SNT + Área No Utilizada")
        println("  • Área Útil = Área Interior + Área Terraza/2")
        println("    (Las terrazas cuentan al 50% para área útil)")
        println("  • Área Común se desglosa en:")
        println("    - Área Pasillo: espacio de circulación asignado a cada departamento")
        println("    - Área Núcleo: espacio adicional (5 m² regular/corner, 10 m² double corner) por cada departamento tipo núcleo")
        println("    - Otros espacios: áreas comunes adicionales (lobbies, salas, etc.)")
        println("  • Área No Utilizada = espacio del emplazamiento no ocupado por deptos ni áreas comunes")
    end

    println("\n" * "="^180)
    println("ASIGNACIÓN DE DEPARTAMENTOS")
    println("="^180)

    all_deptos_global = []

    strip_data = get(results, "strip", Dict())
    tipo_map = Dict("regular"=>"Regular", "regular_nucleo"=>"Núcleo", "corner"=>"Corner", "corner_nucleo"=>"Corner Núcleo", "d_corner_nucleo"=>"D-Corner Núc.")
    tipo_piso_label_map = Dict("primer_piso"=>"1° Piso", "pisos_superiores"=>"Pisos Sup.")

    deptos_dict = get(results, "deptos", Dict())
    for depto_data in values(deptos_dict)
        strip = depto_data["strip"]
        k = depto_data["k"]
        j = depto_data["j"]
        tipo = depto_data["tipo"]
        tipo_label = tipo_map[tipo]

        strip_info = strip_data[strip]
        perimetro_pp = strip_info["perimetro_expuesto"]["primer_piso"]
        perimetro_ps = strip_info["perimetro_expuesto"]["pisos_superiores"]

        profundidad_interior = depto_data["profundidad_interior"]
        ancho_interior = depto_data["ancho_interior"]
        area_interior = depto_data["sup_interior"]
        area_terraza = depto_data["sup_terraza"]
        area_pasillo = depto_data["sup_pasillo"]

        alto = profundidad_interior
        area_nucleo = get(depto_data, "sup_nucleo", 0.0)

        area_total = area_interior + area_pasillo + area_nucleo

        count_pp = depto_data["num_unidades_primer_piso"]
        count_ps = depto_data["num_unidades_por_piso_superior"]

        if count_pp > 0.001
            piso_label = tipo_piso_label_map["primer_piso"]
            perimetro = perimetro_pp
            push!(all_deptos_global, (strip, piso_label, tipo_label, k, j, count_pp, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho_interior, alto, perimetro, profundidad_interior))
        end
        if count_ps > 0.001
            piso_label = tipo_piso_label_map["pisos_superiores"]
            perimetro = perimetro_ps
            push!(all_deptos_global, (strip, piso_label, tipo_label, k, j, count_ps, area_interior, area_pasillo, area_nucleo, area_terraza, area_total, ancho_interior, alto, perimetro, profundidad_interior))
        end
    end

    if !isempty(all_deptos_global)
        println("\n┌──────┬────────────┬──────────────┬──────┬────────┬───────┬──────────┬──────────┬──────────┬─────────┬──────────┬─────────┐")
        println("│Strip │ Piso       │ Tipo         │ (k,j)│ Unid.  │ Ancho │ Prof.    │ Interior │ Pasillo  │ Núcleo  │ Total    │ Terraza │")
        println("│      │            │              │      │        │ (m)   │ (m)      │ (m²)     │ (m²)     │ (m²)    │ (m²)     │ (m²)    │")
        println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼──────────┼─────────┤")

        current_strip = nothing
        for (strip, piso, tipo, k, j, count, area_int, area_pas, area_nuc, area_terr, area_tot, ancho, alto, _, _) in all_deptos_global
            if current_strip !== nothing && strip != current_strip
                println("├──────┼────────────┼──────────────┼──────┼────────┼───────┼──────────┼──────────┼──────────┼─────────┼──────────┼─────────┤")
            end
            current_strip = strip

            println("│  $(lpad(strip, 2))  │ $(rpad(piso, 10)) │ $(rpad(tipo, 12)) │ $(lpad("($k,$j)", 4)) │ $(lpad(round(Int, count), 4))   │ $(lpad(round(ancho, digits=1), 5)) │ $(lpad(round(alto, digits=1), 8)) │ $(lpad(round(area_int, digits=1), 8)) │ $(lpad(round(area_pas, digits=1), 8)) │ $(lpad(round(area_nuc, digits=1), 7)) │ $(lpad(round(area_tot, digits=1), 8)) │ $(lpad(round(area_terr, digits=1), 7)) │")
        end

        println("└──────┴────────────┴──────────────┴──────┴────────┴───────┴──────────┴──────────┴──────────┴─────────┴──────────┴─────────┘")
        println("\nNotas:")
        println("  • Total = Interior + Pasillo + Núcleo")
        println("  • Terraza no está incluida en Total")
    end
    println("\n" * "="^180)
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

    vec_ps_opt = result_vol["vec_ps_opt"]
    vec_np_opt = result_vol["vec_np_opt"]
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

    n_pisos_opt = sum(vec_np_opt)
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
    flag_dfl2 = dict_normativa["flag_dfl2"]

    flag_vivienda_economica = sup_patio_vivienda_economica > 0

    dict_edificio_deptos = opti_planta_edificio(dict_arquitectura, max_constructibilidad, max_deptos, 
                            vec_ps_opt, vec_np_opt, flag_dfl2, flag_vivienda_economica)

    print_results(dict_edificio_deptos)

    # ============================================================================
    # 5. APARTMENT SHAPE COMPILATION
    # ============================================================================
    results = opti_floor_plan(dict_edificio_deptos,
                profundidad_pasillo=profundidad_pasillo,
                min_ancho_pasillo=min_ancho_pasillo,
                max_ancho_terraza=max_ancho_terraza
                )

    results_pisos_superiores = results["pisos_superiores"]
    results_primer_piso = results["primer_piso"]


    # ============================================================================
    # 6. CAPACITY DATA CALCULATION
    # ============================================================================
    df_deptos_resumen = combine(
        groupby(dict_edificio_deptos["df_deptos"], [:strip, :sup_interior, :ancho_interior, :profundidad_interior, :num_unidades_por_piso_superior, :num_unidades_primer_piso]),
        :num_unidades_edificio => sum => :num_unidades_edificio)

    cabida_data = Dict{String, Any}()
    if dict_normativa["tipo_edificio"] == "departamento"
        cabida_data["vec_sup_deptos"] = df_deptos_resumen[:,"sup_interior"]
        cabida_data["vec_num_deptos"] = Int.(round.(df_deptos_resumen[:,"num_unidades_edificio"]))
        cabida_data["vec_sup_comercio"] = 0
        cabida_data["vec_num_comercio"] = 0
        cabida_data["vec_sup_oficinas"] = 0
        cabida_data["vec_num_oficinas"] = 0
    else
        # Safely calculate area, handling empty polygons
        area_edif = 0.0
        for i in eachindex(vec_ps_opt)
            if !isempty(vec_ps_opt[i].Vertices)
                area_edif += polyShape.polyArea(vec_ps_opt[i]) * vec_np_opt[i]
            end
        end
        cabida_data["vec_sup_deptos"] = 0
        cabida_data["vec_num_deptos"] = 0
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
        "proyecto_pisos_snt" => Int8(sum(vec_np_opt[i] for i in eachindex(vec_ps_opt))),
        "proyecto_sup_edificada_bnt" => areaEst_requerida,
        "proyecto_pisos_bnt" => Int8(sum(vec_np_subte[i] for i in eachindex(vec_ps_subte))),
        "proyecto_vec_sup_deptos" => cabida_data["vec_sup_deptos"],
        "proyecto_vec_num_deptos" => cabida_data["vec_num_deptos"],
        "proyecto_vec_num_deptos_primerPiso" => Int.(round.(df_deptos_resumen[:,"num_unidades_primer_piso"])),
        "proyecto_vec_num_deptos_pisosSup" => Int.(round.(df_deptos_resumen[:,"num_unidades_por_piso_superior"])),
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
        "proyecto_supUtil" => dict_edificio_deptos["superficie_interior_edificio"] + 0.5 * dict_edificio_deptos["superficie_terraza_edificio"],
        "proyecto_supUtilPrimerPiso" => dict_edificio_deptos["totals"]["superficie_interior"]["primer_piso"] + 0.5 * dict_edificio_deptos["totals"]["superficie_terraza"]["primer_piso"],
        "proyecto_supUtilPisosSup" => dict_edificio_deptos["totals"]["superficie_interior"]["pisos_superiores"] + 0.5 * dict_edificio_deptos["totals"]["superficie_terraza"]["pisos_superiores"],
        "proyecto_supComun" => dict_edificio_deptos["totals"]["superficie_comun"]["edificio"],
        "proyecto_supComunPrimerPiso" => dict_edificio_deptos["totals"]["superficie_comun"]["primer_piso"],
        "proyecto_supComunPisosSup" => dict_edificio_deptos["totals"]["superficie_comun"]["pisos_superiores"],
        "proyecto_supTerraza" => dict_edificio_deptos["superficie_terraza_edificio"],
        "proyecto_supTerrazaPrimerPiso" => dict_edificio_deptos["totals"]["superficie_terraza"]["primer_piso"],
        "proyecto_supTerrazaPisosSup" => dict_edificio_deptos["totals"]["superficie_terraza"]["pisos_superiores"],
        "proyecto_supInterior" => dict_edificio_deptos["superficie_interior_edificio"],
        "proyecto_supInteriorPrimerPiso" => dict_edificio_deptos["totals"]["superficie_interior"]["primer_piso"],
        "proyecto_supInteriorPisosSup" => dict_edificio_deptos["totals"]["superficie_interior"]["pisos_superiores"],
        "proyecto_descuento_dfl2" => 0.0,
        "proyecto_supNoUtilizada" => dict_edificio_deptos["totals"]["superficie_no_utilizada"]["edificio"],
        "proyecto_numDeptos" => Int(round(dict_edificio_deptos["totals"]["deptos"]["edificio"])),
        "proyecto_vec_ps_opt" => vec_ps_opt,
        "proyecto_vec_np_opt" => vec_np_opt,
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
        "proyecto_constructibilidad" => dict_edificio_deptos["superficie_interior_edificio"] + 0.5 * dict_edificio_deptos["superficie_terraza_edificio"],
        "proyecto_ocupacion_suelo" => isempty(vec_ps_opt) || isempty(vec_ps_opt[1].Vertices) ? 0.0 : polyShape.polyArea(vec_ps_opt[1])
        )

    return dict_proyecto, dict_normativa, dict_edificio_deptos, results_pisos_superiores, results_primer_piso
end