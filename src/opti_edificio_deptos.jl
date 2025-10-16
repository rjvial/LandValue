################################################################################
# RESULTS PROCESSING FUNCTION
################################################################################
function process_optimization_results(model, 
    total_useful_area, useful_area_ground_floor, useful_area_upper_floors,
    total_common_area, common_area_ground_floor, common_area_upper_floors,
    total_terrace_area, terrace_area_ground_floor, terrace_area_upper_floors,
    total_interior_area, interior_area_ground_floor, interior_area_upper_floors,
    unused_area, dfl2_discount, total_apartments,
    apartments_ground_floor, apartments_per_upper_floor, regular_floors)
    
    ############################################################################
    # Check Optimization Status
    ############################################################################
    if termination_status(model) != MOI.OPTIMAL
        @warn "Optimization did not find optimal solution. Status: $(termination_status(model))"
        results = OrderedDict(
            "supUtil" => 0.0,
            "supUtilPrimerPiso" => 0.0,
            "supUtilPisosSup" => 0.0,
            "supComun" => 0.0,
            "supComunPrimerPiso" => 0.0,
            "supComunPisosSup" => 0.0,
            "supTerraza" => 0.0,
            "supTerrazaPrimerPiso" => 0.0,
            "supTerrazaPisosSup" => 0.0,
            "supInterior" => 0.0,
            "supInteriorPrimerPiso" => 0.0,
            "supInteriorPisosSup" => 0.0,
            "descuento_dfl2" => 0.0,
            "supNoUtilizada" => 0.0,
            "vec_numDeptosTipo" => Int[],
            "vec_numDeptosTipo_primerPiso" => Int[],
            "vec_numDeptosTipo_pisosSup" => Int[],
            "numDeptos" => 0
        )

    else

        ############################################################################
        # Extract Optimization Values
        ############################################################################
        results = OrderedDict(
            "supUtil" => round(value(total_useful_area), digits=2),
            "supUtilPrimerPiso" => round(value(useful_area_ground_floor), digits=2),
            "supUtilPisosSup" => round(value(useful_area_upper_floors), digits=2),
            "supComun" => round(value(total_common_area), digits=2),
            "supComunPrimerPiso" => round(value(common_area_ground_floor), digits=2),
            "supComunPisosSup" => round(value(common_area_upper_floors), digits=2),
            "supTerraza" => round(value(total_terrace_area), digits=2),
            "supTerrazaPrimerPiso" => round(value(terrace_area_ground_floor), digits=2),
            "supTerrazaPisosSup" => round(value(terrace_area_upper_floors), digits=2),
            "supInterior" => round(value(total_interior_area), digits=2),
            "supInteriorPrimerPiso" => round(value(interior_area_ground_floor), digits=2),
            "supInteriorPisosSup" => round(value(interior_area_upper_floors), digits=2),
            "descuento_dfl2" => round(value(dfl2_discount), digits=2),
            "supNoUtilizada" => round(value(unused_area), digits=2),
            "vec_numDeptosTipo_primerPiso" => [round(Int, value(apartments_ground_floor[u])) for u in axes(apartments_ground_floor, 1)],
            "vec_numDeptosTipo_pisosSup" => [round(Int, value(apartments_per_upper_floor[u]) * regular_floors) for u in axes(apartments_ground_floor, 1)],
            "vec_numDeptosTipo" => [round(Int, value(apartments_ground_floor[u]) + value(apartments_per_upper_floor[u]) * regular_floors) for u in axes(apartments_ground_floor, 1)],
            "numDeptos" => round(Int8, value(total_apartments))
        )
        
        ############################################################################
        # Display Results Summary
        ############################################################################
        println("\n=== Optimization Results Summary ===")
        println("Ground Floor | Upper Floors | Total")
        println("-" ^ 40)
        
        areas = [
            ("Common", "supComunPrimerPiso", "supComunPisosSup", "supComun"),
            ("Terrace", "supTerrazaPrimerPiso", "supTerrazaPisosSup", "supTerraza"),
            ("Interior", "supInteriorPrimerPiso", "supInteriorPisosSup", "supInterior")
        ]
        
        # Calculate column totals
        ground_floor_total = 0.0
        upper_floors_total = 0.0
        grand_total = 0.0
        
        # Display each row with totals
        for (name, ground_key, upper_key, total_key) in areas
            ground_val = round(results[ground_key], digits=1)
            upper_val = round(results[upper_key], digits=1)
            total_val = round(results[total_key], digits=1)
            
            ground_floor_total += ground_val
            upper_floors_total += upper_val
            grand_total += total_val
            
            println("$(rpad(name, 8)) = $(rpad(ground_val, 11)) | $(rpad(upper_val, 12)) | $(total_val)")
        end
        
        # Display column totals
        println("-" ^ 40)
        println("$(rpad("TOTALS", 8)) = $(rpad(round(ground_floor_total, digits=1), 11)) | $(rpad(round(upper_floors_total, digits=1), 12)) | $(round(grand_total, digits=1))")
        
        println("-" ^ 40)
        println("Total Useful Area: $(round(results["supUtil"], digits=1)) m²")
        println("Total Apartments: $(round(Int, results["numDeptos"]))")
        println("Apartments by type: $(results["vec_numDeptosTipo"])")
        println("=" ^ 40)

    end
    
    return results
end


################################################################################
# MAIN OPTIMIZATION FUNCTION
################################################################################
function opti_edificio_deptos(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, 
                                flag_dfl2, sup_patio_vivienda_economica, superficie_terreno)
    # Optimizes apartment distribution in a multi-story building to maximize useful area while respecting regulatory constraints.
    
    ############################################################################
    # Building Geometry Setup
    ############################################################################
    num_stacks = length(vec_ps_opt)
    basal_areas = [polyShape.polyArea(ps) for ps in vec_ps_opt]
    total_floors = sum(vec_np_opt)
    regular_floors = total_floors - 1  # Upper floors (excluding ground floor)

    ############################################################################
    # Apartment Type Specifications
    ############################################################################
    num_apartment_types = length(dict_arquitectura["arq_vecSupUtil"])
    useful_areas = dict_arquitectura["arq_vecSupUtil"]
    terrace_areas = dict_arquitectura["arq_vecSupTerraza"]
    interior_areas = dict_arquitectura["arq_vecSupInterior"]
    
    # DFL2 eligibility: apartments ≤ 140m² qualify
    dfl2_eligible = [useful_areas[i] <= 140 ? 1 : 0 for i in 1:num_apartment_types]

    ############################################################################
    # Optimization Model Setup
    ############################################################################
    model = Model(Cbc.Optimizer)
    set_optimizer_attribute(model, "ratioGap", 0.001)
    set_optimizer_attribute(model, "logLevel", 0)

    apartments = 1:num_apartment_types

    ############################################################################
    # Decision Variables
    ############################################################################
    @variables(model, begin
        apartments_ground_floor[u=1:num_apartment_types] >= 0, Int
        apartments_per_upper_floor[u=1:num_apartment_types] >= 0, Int
        common_area_ground_floor >= 0
        common_area_upper_floors >= 0
        dfl2_discount >= 0
        unused_area >= 0
        z[u=1:num_apartment_types], Bin
        y[u=1:num_apartment_types], Bin
    end)

    ############################################################################
    # Calculated Expressions
    ############################################################################
    @expression(model, useful_area_ground_floor, 
        sum(useful_areas[u] * apartments_ground_floor[u] for u=1:num_apartment_types))
    @expression(model, useful_area_upper_floors, 
        sum(useful_areas[u] * apartments_per_upper_floor[u] * regular_floors for u=1:num_apartment_types))
    @expression(model, total_useful_area, useful_area_ground_floor + useful_area_upper_floors)

    @expression(model, terrace_area_ground_floor, 
        sum(terrace_areas[u] * apartments_ground_floor[u] for u=1:num_apartment_types))
    @expression(model, terrace_area_upper_floors, 
        sum(terrace_areas[u] * apartments_per_upper_floor[u] * regular_floors for u=1:num_apartment_types))
    @expression(model, total_terrace_area, terrace_area_ground_floor + terrace_area_upper_floors)

    @expression(model, interior_area_ground_floor, 
        sum(interior_areas[u] * apartments_ground_floor[u] for u=1:num_apartment_types))
    @expression(model, interior_area_upper_floors, 
        sum(interior_areas[u] * apartments_per_upper_floor[u] * regular_floors for u=1:num_apartment_types))
    @expression(model, total_interior_area, interior_area_ground_floor + interior_area_upper_floors)

    @expression(model, total_common_area, common_area_ground_floor + common_area_upper_floors)
    @expression(model, total_apartments, 
        sum(apartments_ground_floor) + sum(apartments_per_upper_floor) * regular_floors)

    ############################################################################
    # Optimization Constraints
    ############################################################################
    @constraint(model, total_apartments_constraint_max, sum(apartments_ground_floor) + sum(apartments_per_upper_floor) * regular_floors <= max_deptos)
    @constraint(model, total_apartments_constraint_min, sum(apartments_ground_floor) + sum(apartments_per_upper_floor) * regular_floors >= max_deptos - 2)


    # Common area constraints
    @constraint(model, dfl2_discount_useful_area_limit, dfl2_discount <= flag_dfl2 * 0.2 * total_useful_area)
    @constraint(model, dfl2_discount_common_area_limit, dfl2_discount <= flag_dfl2 * total_common_area)
    @constraint(model, common_area_ground_floor_min, common_area_ground_floor >= dict_arquitectura["arq_coefSupComunPrimerPiso"] * useful_area_ground_floor)
    @constraint(model, common_area_upper_floors_min, common_area_upper_floors >= dict_arquitectura["arq_coefSupComunPisosSup"] * useful_area_upper_floors)
    @constraint(model, total_common_area_min, total_common_area >= dict_arquitectura["arq_coefSupComun"] * total_useful_area)
    @constraint(model, total_common_area_max, total_common_area <= 0.25 * total_useful_area)

    @constraint(model, z_binary_constraints[u=1:num_apartment_types], apartments_ground_floor[u] + apartments_per_upper_floor[u] <= z[u] * max_deptos)

    for i in apartments, j in apartments
        if interior_areas[i] < interior_areas[j]  # avoid duplicate constraints
            if interior_areas[j] > interior_areas[i] * 2.5 #3.4
                @constraint(model, z[i] + z[j] <= 1)
            end
        end
    end

    # Link indicator to ground floor usage
    for u in 1:num_apartment_types
        @constraint(model, apartments_ground_floor[u] <= max_deptos * y[u])
        @constraint(model, apartments_ground_floor[u] >= y[u])
    end

    # Only enforce equal quantities IF apartment type is used on ground floor
    for u in 1:num_apartment_types
        @constraint(model, apartments_ground_floor[u] <= apartments_per_upper_floor[u] + max_deptos * (1 - y[u]))
        @constraint(model, apartments_ground_floor[u] >= apartments_per_upper_floor[u] - max_deptos * (1 - y[u]))
    end


    # Buildability constraint
    @constraint(model, buildability_limit, total_useful_area + total_common_area - dfl2_discount <= max_constructibilidad)
    
    # Total area balance
    @constraint(model, total_area_balance, unused_area + total_common_area + total_terrace_area + total_interior_area == 
        sum(basal_areas[k] * vec_np_opt[k] for k=1:num_stacks))

    # DFL2 apartment type restrictions
    if flag_dfl2 || (sup_patio_vivienda_economica > 0)
        @constraint(model, dfl2_apartment_type_restriction[u=1:num_apartment_types], 
            apartments_ground_floor[u] + apartments_per_upper_floor[u] * regular_floors <= dfl2_eligible[u] * max_deptos)
    end

    ############################################################################
    # Objective Function and Solve
    ############################################################################
    @objective(model, Max, total_useful_area)
    optimize!(model)

    ############################################################################
    # Return Results
    ############################################################################
    return process_optimization_results(model, 
        total_useful_area, useful_area_ground_floor, useful_area_upper_floors,
        total_common_area, common_area_ground_floor, common_area_upper_floors,
        total_terrace_area, terrace_area_ground_floor, terrace_area_upper_floors,
        total_interior_area, interior_area_ground_floor, interior_area_upper_floors,
        unused_area, dfl2_discount, total_apartments,
        apartments_ground_floor, apartments_per_upper_floor, regular_floors)
end


