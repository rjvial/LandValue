using JuMP
using HiGHS

"""
    optim_asignacion_deptos(W, H, num_strips, set_i, set_w, vec_w, mat_h, vec_area_interior, vec_area_pasillo, vec_w_terraza, vec_h_terraza, vec_area_terraza, mat_exposicion, mat_exposicion_corner, mat_exposicion_double_corner, min_deptos, max_deptos)

Optimiza la asignación de departamentos en strips horizontales para maximizar superficie total.

# Argumentos
- `W::Float64`: Ancho del edificio (m)
- `H::Float64`: Altura total del edificio (m)
- `num_strips::Int`: Número de strips horizontales
- `set_i::Vector{Int}`: Conjunto de índices de tipos de departamentos
- `set_w::Vector{Int}`: Conjunto de índices de alturas
- `vec_w`: Vector de anchos por tipo de departamento i
- `mat_h`: Matriz de alturas [i,h] por tipo de departamento e índice de altura
- `vec_area_interior`: Vector de áreas por tipo i
- `vec_area_pasillo`: Vector de áreas de pasillo por tipo i
- `vec_w_terraza`: Vector de anchos de terraza por tipo i
- `vec_h_terraza`: Vector de alturas de terraza por tipo i
- `vec_area_terraza`: Vector de áreas de terraza por tipo i
- `mat_exposicion, mat_exposicion_corner, mat_exposicion_double_corner`: Matrices de perímetros [i,h] (regular, corner, corner2)
- `min_deptos::Int`: Número mínimo de departamentos
- `max_deptos::Int`: Número máximo de departamentos

# Tipos de departamentos
- `z`: Departamentos regulares
- `z_c`: Departamentos en esquina (corner) - siempre 2 por strip
- `z_cc`: Departamentos en esquina doble (corner2) - máximo 1 por strip

# Returns
- `Dict{String,Any}`: Diccionario con resultados de optimización
"""
function optim_asignacion_deptos(
    W::Float64,
    H::Float64,
    num_strips::Int,
    vec_w, mat_h, vec_area_interior, vec_area_pasillo,
    vec_w_terraza, vec_h_terraza, vec_area_terraza,
    mat_exposicion, mat_exposicion_corner, mat_exposicion_double_corner,
    min_deptos::Int,
    max_deptos::Int,
    num_pisos,
    max_constructibilidad)

    flag_dfl2 = true

    num_pisos_superiores = num_pisos - 1

    num_areas_deptos = length(vec_area_interior)
    set_i = 1:num_areas_deptos

    num_widths = size(mat_h, 2)
    set_w = 1:num_widths

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.01)
    set_optimizer_attribute(model, "presolve", "on")

    S = 1:num_strips

    max_z_bounds = Dict()
    for i in set_i, j in set_w
        if (mat_h[i,j] + vec_h_terraza[i]) <= H && vec_w[i] <= W
            max_by_width = floor(Int, W / vec_w[i])
            max_by_height = floor(Int, H / (mat_h[i,j] + vec_h_terraza[i]))
            max_by_area = floor(Int, (W * H) / (vec_area_interior[i] + vec_area_terraza[i]))
            max_z_bounds[(i,j)] = min(max_by_width, max_by_height, max_by_area, max_deptos)
        else
            max_z_bounds[(i,j)] = 0
        end
    end

    @variables(model, begin
        H_s[s in S] >= 0

        0 <= num_deptos_reg_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_corner_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_double_corner_primer_piso[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        area_comun_primer_piso >= 0

        0 <= num_deptos_reg_pisos_superiores[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_corner_pisos_superiores[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        0 <= num_deptos_double_corner_pisos_superiores[s in S, i in set_i, j in set_w] <= max_z_bounds[(i,j)], Int
        area_comun_pisos_superiores >= 0

        x[s in S, i in set_i, j in set_w], Bin
        x_c[s in S, i in set_i, j in set_w], Bin
        x_cc[s in S, i in set_i, j in set_w], Bin

        y_c[s in S], Bin
        y_cc[s in S], Bin

        descuento_dfl2 >= 0
    end)

    @expression(model, area_comun_total, area_comun_primer_piso + area_comun_pisos_superiores)

    # Total surface area of all apartments (objective function value)
    @expression(model, area_interior_primer_piso,
        sum((num_deptos_reg_primer_piso[s,i,j] +
             num_deptos_corner_primer_piso[s,i,j] +
             num_deptos_double_corner_primer_piso[s,i,j]) * vec_area_interior[i] for s in S, i in set_i, j in set_w)
    )
    @expression(model, area_interior_pisos_superiores,
        sum((num_deptos_reg_pisos_superiores[s,i,j] +
             num_deptos_corner_pisos_superiores[s,i,j] +
             num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_area_interior[i] * num_pisos_superiores for s in S, i in set_i, j in set_w)
    )
    @expression(model, area_interior_total, area_interior_primer_piso + area_interior_pisos_superiores)

    @expression(model, area_terraza_primer_piso,
        sum((num_deptos_reg_primer_piso[s,i,j] +
             num_deptos_corner_primer_piso[s,i,j] +
             num_deptos_double_corner_primer_piso[s,i,j]) * vec_area_terraza[i] for s in S, i in set_i, j in set_w)
    )
    @expression(model, area_terraza_pisos_superiores,
        sum((num_deptos_reg_pisos_superiores[s,i,j] +
             num_deptos_corner_pisos_superiores[s,i,j] +
             num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_area_terraza[i] * num_pisos_superiores for s in S, i in set_i, j in set_w)
    )
    @expression(model, area_terraza_total, area_terraza_primer_piso + area_terraza_pisos_superiores)

    @expression(model, area_util_primer_piso, area_interior_primer_piso + area_terraza_primer_piso / 2)
    @expression(model, area_util_pisos_superiores, area_interior_pisos_superiores + area_terraza_pisos_superiores / 2)
    @expression(model, area_util_total, area_util_primer_piso + area_util_pisos_superiores)

    
    # Buildability constraint
    @constraint(model, buildability_limit, area_util_total + area_comun_total - descuento_dfl2 <= max_constructibilidad)
    @constraint(model, dfl2_discount_useful_area_limit, descuento_dfl2 <= flag_dfl2 * 0.2 * area_util_total)
    @constraint(model, dfl2_discount_common_area_limit, descuento_dfl2 <= flag_dfl2 * area_comun_total)
    @constraint(model, common_area_upper_floors_min, area_comun_pisos_superiores >= 0.12 * area_util_pisos_superiores) # "arq_coefSupComunPisosSup" => 0.12,
    @constraint(model, total_common_area_min, area_comun_total >= 0.18 * area_util_total) # "arq_coefSupComun" => 0.18,
    @constraint(model, total_common_area_max, area_comun_total <= 0.25 * area_util_total)



    # Exactly 2 corner apartments per strip if corner type is used
    @constraint(model, constraint_uso_strip_c[s in S],
        sum(num_deptos_corner_pisos_superiores[s,i,j] for i in set_i, j in set_w) == 2 * y_c[s]
    )

    # Exactly 1 double corner apartment per strip if double corner type is used
    @constraint(model, constraint_uso_strip_cc[s in S],
        sum(num_deptos_double_corner_pisos_superiores[s,i,j] for i in set_i, j in set_w) == y_cc[s]
    )
    # Allows only one double corner apartment or several regular apartments. Not both.
    @constraint(model, constraint_y_cc[s in S],
        sum(x_cc[s,i,j] + x[s,i,j] for i in set_i, j in set_w) <= y_cc[s] + (1 - y_cc[s]) * max_deptos
    )
    # Strip can use either corner or double corner, not both
    @constraint(model, constraint_corner_c_o_cc[s in S],
        y_c[s] + y_cc[s] <= 1
    )

    # Total count of all apartment types across all strips and floors
    @expression(model, deptos_total,
        (sum(num_deptos_reg_primer_piso[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(num_deptos_corner_primer_piso[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(num_deptos_double_corner_primer_piso[s,i,j] for s in S, i in set_i, j in set_w)) +
        (sum(num_deptos_reg_pisos_superiores[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(num_deptos_corner_pisos_superiores[s,i,j] for s in S, i in set_i, j in set_w) +
        sum(num_deptos_double_corner_pisos_superiores[s,i,j] for s in S, i in set_i, j in set_w)) * num_pisos_superiores
    )
    # Total apartment count must be within specified bounds
    @constraint(model, constraint_min_max_deptos,
        min_deptos <= deptos_total <= max_deptos
    )

    # Sum of all strip depths cannot exceed building depth
    @constraint(model, constraint_suma_profundidades,
        sum(H_s[s] for s in S) <= H
    )

    # Each strip must have minimum depth of 7.0m
    @constraint(model, constraint_profundidad_strip[s in S],
        H_s[s] >= 8.0
    )


    # Apartment height must fit within strip depth
    @constraints(model, begin
        constraint_profundidad_strip_z[s in S, i in set_i, j in set_w], x[s,i,j] * (mat_h[i,j] + vec_h_terraza[i]) <= H_s[s]
        constraint_profundidad_strip_z_c[s in S, i in set_i, j in set_w], x_c[s,i,j] * (mat_h[i,j] + vec_h_terraza[i]) <= H_s[s]
        constraint_profundidad_strip_z_cc[s in S, i in set_i, j in set_w], x_cc[s,i,j] * (mat_h[i,j] + vec_h_terraza[i]) <= H_s[s]
    end)


    # Total apartment area per strip cannot exceed strip footprint
    @constraint(model, constraint_area_strip[s in S],
        sum((num_deptos_reg_pisos_superiores[s,i,j] + 
             num_deptos_corner_pisos_superiores[s,i,j] + 
             num_deptos_double_corner_pisos_superiores[s,i,j]) * (vec_area_interior[i] + vec_area_terraza[i]) for i in set_i, j in set_w) <= W * H_s[s]
    )


    # Apartment count is positive only if apartment type is selected (Big-M)
    @constraints(model, begin
        constraint_big_m_z[s in S, i in set_i, j in set_w], num_deptos_reg_pisos_superiores[s,i,j] <= max_deptos * x[s,i,j]
        constraint_big_m_z_c[s in S, i in set_i, j in set_w], num_deptos_corner_pisos_superiores[s,i,j] <= max_deptos * x_c[s,i,j]
        constraint_big_m_z_cc[s in S, i in set_i, j in set_w], num_deptos_double_corner_pisos_superiores[s,i,j] <= max_deptos * x_cc[s,i,j]
    end)


    # Total apartment widths per strip cannot exceed building width
    @constraint(model, constraint_ancho_strip[s in S],
        sum((num_deptos_reg_pisos_superiores[s,i,j] + 
        num_deptos_corner_pisos_superiores[s,i,j] + 
        num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_w[i] for i in set_i, j in set_w) <= W
    )

    # Apartment perimeters must cover strip perimeter (ensures full coverage)
    @constraint(model, constraint_perimetro[s in S],
        sum(num_deptos_reg_pisos_superiores[s,i,j] * mat_exposicion[i,j] for i in set_i, j in set_w) +
        sum(num_deptos_corner_pisos_superiores[s,i,j] * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
        sum(num_deptos_double_corner_pisos_superiores[s,i,j] * mat_exposicion_double_corner[i,j] for i in set_i, j in set_w) >= 2*H_s[s] + W - 5
    )

    @constraints(model, begin 
        constraint_primer_piso[s in S, i in set_i, j in set_w], 
            num_deptos_reg_primer_piso[s,i,j] <= num_deptos_reg_pisos_superiores[s,i,j]
        constraint_primer_piso_c[s in S, i in set_i, j in set_w], 
            num_deptos_corner_primer_piso[s,i,j] <= num_deptos_corner_pisos_superiores[s,i,j]
        constraint_primer_piso_cc[s in S, i in set_i, j in set_w], 
            num_deptos_double_corner_primer_piso[s,i,j] <= num_deptos_double_corner_pisos_superiores[s,i,j]
    end)

    # Maximize total apartment interior area
    @objective(model, Max, area_interior_total)

    optimize!(model)


    
    results = Dict{String,Any}()
    results["status"] = termination_status(model)
    results["solve_time"] = solve_time(model)
    results["z"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_c"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z_cc"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z0"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z0_c"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["z0_cc"] = Dict{Tuple{Int,Int,Int},Float64}()
    results["x"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_c"] = Dict{Tuple{Int,Int,Int},Int}()
    results["x_cc"] = Dict{Tuple{Int,Int,Int},Int}()
    results["H_s"] = Dict{Int,Float64}()
    results["perimetro_strip_primer_piso"] = Dict{Int,Float64}()
    results["apartment_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["terrace_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["pasillo_area_strip_primer_piso"] = Dict{Int,Float64}()
    results["perimetro_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["apartment_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["terrace_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["pasillo_area_strip_pisos_superiores"] = Dict{Int,Float64}()
    results["vec_area_terraza"] = vec_area_terraza
    results["vec_w_terraza"] = vec_w_terraza
    results["vec_h_terraza"] = vec_h_terraza
    results["vec_area_interior"] = vec_area_interior
    results["vec_area_pasillo"] = vec_area_pasillo
    results["vec_w"] = vec_w
    results["mat_h"] = mat_h

    if has_values(model)
        results["objective_value"] = objective_value(model)

        for s in S
            results["H_s"][s] = value(H_s[s])

            perimetro_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * mat_exposicion[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_corner_primer_piso[s,i,j]) * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_double_corner_primer_piso[s,i,j]) * mat_exposicion_double_corner[i,j] for i in set_i, j in set_w)
            results["perimetro_strip_primer_piso"][s] = perimetro_s_pp

            apartment_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_double_corner_primer_piso[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w)
            results["apartment_area_strip_primer_piso"][s] = apartment_area_s_pp

            terrace_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_double_corner_primer_piso[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w)
            results["terrace_area_strip_primer_piso"][s] = terrace_area_s_pp

            pasillo_area_s_pp = sum(value(num_deptos_reg_primer_piso[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_primer_piso[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_double_corner_primer_piso[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w)
            results["pasillo_area_strip_primer_piso"][s] = pasillo_area_s_pp

            perimetro_s_ps = sum(value(num_deptos_reg_pisos_superiores[s,i,j]) * mat_exposicion[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_corner_pisos_superiores[s,i,j]) * mat_exposicion_corner[i,j] for i in set_i, j in set_w) +
                          sum(value(num_deptos_double_corner_pisos_superiores[s,i,j]) * mat_exposicion_double_corner[i,j] for i in set_i, j in set_w)
            results["perimetro_strip_pisos_superiores"][s] = perimetro_s_ps

            apartment_area_s_ps = sum(value(num_deptos_reg_pisos_superiores[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_corner_pisos_superiores[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w) +
                               sum(value(num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_area_interior[i] for i in set_i, j in set_w)
            results["apartment_area_strip_pisos_superiores"][s] = apartment_area_s_ps

            terrace_area_s_ps = sum(value(num_deptos_reg_pisos_superiores[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_pisos_superiores[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_area_terraza[i] for i in set_i, j in set_w)
            results["terrace_area_strip_pisos_superiores"][s] = terrace_area_s_ps

            pasillo_area_s_ps = sum(value(num_deptos_reg_pisos_superiores[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_corner_pisos_superiores[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w) +
                             sum(value(num_deptos_double_corner_pisos_superiores[s,i,j]) * vec_area_pasillo[i] for i in set_i, j in set_w)
            results["pasillo_area_strip_pisos_superiores"][s] = pasillo_area_s_ps

            for i in set_i, h in set_w
                for (var, key, threshold, is_binary) in [
                    (num_deptos_reg_pisos_superiores[s,i,h], "z", 0.001, false),
                    (num_deptos_corner_pisos_superiores[s,i,h], "z_c", 0.001, false),
                    (num_deptos_double_corner_pisos_superiores[s,i,h], "z_cc", 0.001, false),
                    (num_deptos_reg_primer_piso[s,i,h], "z0", 0.001, false),
                    (num_deptos_corner_primer_piso[s,i,h], "z0_c", 0.001, false),
                    (num_deptos_double_corner_primer_piso[s,i,h], "z0_cc", 0.001, false),
                    (x[s,i,h], "x", 0.5, true),
                    (x_c[s,i,h], "x_c", 0.5, true),
                    (x_cc[s,i,h], "x_cc", 0.5, true)]

                    val = value(var)
                    if val > threshold
                        results[key][(s,i,h)] = is_binary ? 1 : val
                    end
                end
            end
        end

        deptos_primer_piso = sum(sum(values(results[k])) for k in ["z0", "z0_c", "z0_cc"])
        deptos_pisos_superiores = sum(sum(values(results[k])) for k in ["z", "z_c", "z_cc"])

        results["total_deptos_primer_piso"] = deptos_primer_piso
        results["total_deptos_pisos_superiores"] = deptos_pisos_superiores
        results["total_deptos"] = deptos_primer_piso + deptos_pisos_superiores * num_pisos_superiores

        results["total_apartment_area_primer_piso"] = sum(values(results["apartment_area_strip_primer_piso"]))
        results["total_terrace_area_primer_piso"] = sum(values(results["terrace_area_strip_primer_piso"]))
        results["total_pasillo_area_primer_piso"] = sum(values(results["pasillo_area_strip_primer_piso"]))

        results["total_apartment_area_pisos_superiores"] = sum(values(results["apartment_area_strip_pisos_superiores"]))
        results["total_terrace_area_pisos_superiores"] = sum(values(results["terrace_area_strip_pisos_superiores"]))
        results["total_pasillo_area_pisos_superiores"] = sum(values(results["pasillo_area_strip_pisos_superiores"]))

        results["total_area_pisos_superiores"] = (results["total_apartment_area_pisos_superiores"] + results["total_terrace_area_pisos_superiores"] + results["total_pasillo_area_pisos_superiores"]) * num_pisos_superiores

        results["total_apartment_area_building"] = results["total_apartment_area_primer_piso"] + results["total_apartment_area_pisos_superiores"] * num_pisos_superiores
        results["total_terrace_area_building"] = results["total_terrace_area_primer_piso"] + results["total_terrace_area_pisos_superiores"] * num_pisos_superiores
        results["total_pasillo_area_building"] = results["total_pasillo_area_primer_piso"] + results["total_pasillo_area_pisos_superiores"] * num_pisos_superiores
        results["total_area_building"] = results["total_apartment_area_building"] + results["total_terrace_area_building"] + results["total_pasillo_area_building"]

        results["num_pisos_superiores"] = num_pisos_superiores
        results["num_pisos_total"] = num_pisos
    else
        results["objective_value"] = nothing
        results["total_deptos"] = 0.0
        println("\n⚠️  WARNING: No feasible solution found!")
        println("Status: $(results["status"])")
    end

    return results
end

function print_results(results::Dict)
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
        total_deptos_pp = get(results, "total_deptos_primer_piso", 0.0)
        total_deptos_ps = get(results, "total_deptos_pisos_superiores", 0.0)
        total_deptos = get(results, "total_deptos", 0.0)
        num_pisos_sup = get(results, "num_pisos_superiores", 1)

        println("Total departamentos edificio: $(round(total_deptos, digits=0))")
        println("  - Primer piso: $(round(total_deptos_pp, digits=0)) deptos")
        println("  - Pisos superiores: $(round(total_deptos_ps, digits=0)) deptos/piso × $(num_pisos_sup) pisos = $(round(total_deptos_ps * num_pisos_sup, digits=0)) deptos")
    else
        println("Total departamentos: 0")
    end

    if !isnothing(results["objective_value"])
        area_interior_pp = get(results, "total_apartment_area_primer_piso", 0.0)
        area_terraza_pp = get(results, "total_terrace_area_primer_piso", 0.0)
        area_pasillo_pp = get(results, "total_pasillo_area_primer_piso", 0.0)
        area_util_pp = area_interior_pp + area_terraza_pp / 2

        area_interior_ps = get(results, "total_apartment_area_pisos_superiores", 0.0)
        area_terraza_ps = get(results, "total_terrace_area_pisos_superiores", 0.0)
        area_pasillo_ps = get(results, "total_pasillo_area_pisos_superiores", 0.0)
        area_util_ps = area_interior_ps + area_terraza_ps / 2

        num_pisos_sup = get(results, "num_pisos_superiores", 1)
        num_pisos_total = get(results, "num_pisos_total", 1)

        area_total_losa_pp = area_interior_pp + area_terraza_pp + area_pasillo_pp
        area_total_losa_ps = area_interior_ps + area_terraza_ps + area_pasillo_ps
        area_total_losa_edificio = area_total_losa_pp + area_total_losa_ps * num_pisos_sup

        println("\n" * "="^80)
        println("RESUMEN DE ÁREAS POR PISO")
        println("="^80)
        println("")
        println("┌─────────────────────┬──────────────────┬──────────────────┬──────────────────┐")
        println("│                     │  Primer Piso     │  Piso Superior   │  Total Edificio  │")
        println("│                     │    (1 piso)      │   (por piso)     │   ($(num_pisos_total) pisos)      │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Interior       │ $(lpad(round(area_interior_pp, digits=1), 12)) m² │ $(lpad(round(area_interior_ps, digits=1), 12)) m² │ $(lpad(round(area_interior_pp + area_interior_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Terraza        │ $(lpad(round(area_terraza_pp, digits=1), 12)) m² │ $(lpad(round(area_terraza_ps, digits=1), 12)) m² │ $(lpad(round(area_terraza_pp + area_terraza_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ Área Pasillo        │ $(lpad(round(area_pasillo_pp, digits=1), 12)) m² │ $(lpad(round(area_pasillo_ps, digits=1), 12)) m² │ $(lpad(round(area_pasillo_pp + area_pasillo_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Total de Losa  │ $(lpad(round(area_total_losa_pp, digits=1), 12)) m² │ $(lpad(round(area_total_losa_ps, digits=1), 12)) m² │ $(lpad(round(area_total_losa_edificio, digits=1), 12)) m² │")
        println("├─────────────────────┼──────────────────┼──────────────────┼──────────────────┤")
        println("│ Área Útil           │ $(lpad(round(area_util_pp, digits=1), 12)) m² │ $(lpad(round(area_util_ps, digits=1), 12)) m² │ $(lpad(round(area_util_pp + area_util_ps * num_pisos_sup, digits=1), 12)) m² │")
        println("│ (Interior + Terr/2) │                  │                  │                  │")
        println("└─────────────────────┴──────────────────┴──────────────────┴──────────────────┘")
        println("")
        println("Notas:")
        println("  • Área Total de Losa = Área Interior + Área Terraza + Área Pasillo")
        println("  • Área Útil = Área Interior + Área Terraza/2")
        println("    (Las terrazas cuentan al 50% para área útil)")
    end

    println("\n" * "-"^60)
    println("ASIGNACIÓN POR STRIP - PRIMER PISO:")
    println("-"^60)

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro = get(results["perimetro_strip_primer_piso"], strip, 0.0)
        apt_area = get(results["apartment_area_strip_primer_piso"], strip, 0.0)
        terrace_area = get(results["terrace_area_strip_primer_piso"], strip, 0.0)
        pasillo_area = get(results["pasillo_area_strip_primer_piso"], strip, 0.0)
        println("\nStrip $strip - profundidad: $(round(profundidad, digits=2)) m - Perímetro: $(round(perimetro, digits=2)) m")
        println("  Área departamentos: $(round(apt_area, digits=2)) m²")
        println("  Área terrazas: $(round(terrace_area, digits=2)) m²")
        println("  Área pasillos: $(round(pasillo_area, digits=2)) m²")

        for (key, label) in [("z0", "regulares"), ("z0_c", "corner"), ("z0_cc", "corner 2")]
            strip_deptos = filter(p -> p[1][1] == strip, collect(get(results, key, Dict())))
            if !isempty(strip_deptos)
                println("  Deptos $label:")
                vec_area_interior = results["vec_area_interior"]
                vec_area_terraza = results["vec_area_terraza"]
                vec_area_pasillo = results["vec_area_pasillo"]
                vec_h_terraza = results["vec_h_terraza"]
                for ((s, i, h), count) in strip_deptos
                    apt_area_unit = vec_area_interior[i]
                    t_area = vec_area_terraza[i]
                    p_area = vec_area_pasillo[i]
                    t_height = vec_h_terraza[i]
                    println("    Tipo ($i,$h): $(round(count, digits=0)) unidades - Depto: $(round(apt_area_unit, digits=2)) m² | Terraza: $(round(t_area, digits=2)) m² | Pasillo: $(round(p_area, digits=2)) m² (prof: $(round(t_height, digits=2)) m)")
                end
            end
        end
    end

    println("\n" * "-"^60)
    println("ASIGNACIÓN POR STRIP - PISOS SUPERIORES:")
    println("-"^60)

    for (strip, profundidad) in sort(collect(results["H_s"]))
        perimetro = get(results["perimetro_strip_pisos_superiores"], strip, 0.0)
        apt_area = get(results["apartment_area_strip_pisos_superiores"], strip, 0.0)
        terrace_area = get(results["terrace_area_strip_pisos_superiores"], strip, 0.0)
        pasillo_area = get(results["pasillo_area_strip_pisos_superiores"], strip, 0.0)
        println("\nStrip $strip - profundidad: $(round(profundidad, digits=2)) m - Perímetro: $(round(perimetro, digits=2)) m")
        println("  Área departamentos: $(round(apt_area, digits=2)) m²")
        println("  Área terrazas: $(round(terrace_area, digits=2)) m²")
        println("  Área pasillos: $(round(pasillo_area, digits=2)) m²")

        for (key, label) in [("z", "regulares"), ("z_c", "corner"), ("z_cc", "corner 2")]
            strip_deptos = filter(p -> p[1][1] == strip, collect(results[key]))
            if !isempty(strip_deptos)
                println("  Deptos $label:")
                vec_area_interior = results["vec_area_interior"]
                vec_area_terraza = results["vec_area_terraza"]
                vec_area_pasillo = results["vec_area_pasillo"]
                vec_h_terraza = results["vec_h_terraza"]
                for ((s, i, h), count) in strip_deptos
                    apt_area_unit = vec_area_interior[i]
                    t_area = vec_area_terraza[i]
                    p_area = vec_area_pasillo[i]
                    t_height = vec_h_terraza[i]
                    println("    Tipo ($i,$h): $(round(count, digits=0)) unidades - Depto: $(round(apt_area_unit, digits=2)) m² | Terraza: $(round(t_area, digits=2)) m² | Pasillo: $(round(p_area, digits=2)) m² (prof: $(round(t_height, digits=2)) m)")
                end
            end
        end
    end
    println("\n" * "="^60)
end
