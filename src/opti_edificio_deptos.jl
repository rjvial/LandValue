"""
    opti_edificio_deptos(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, flag_dfl2, sup_patio_vivienda_economica, superficie_terreno)

Optimizes apartment distribution in a multi-story building to maximize useful area while respecting regulatory constraints.

# Arguments
- `dict_arquitectura::Dict`: Architecture specifications including apartment types and area coefficients
- `max_constructibilidad::Float64`: Maximum buildable area allowed
- `max_deptos::Int`: Maximum number of apartments
- `vec_ps_opt::Vector`: Optimized building geometry polygons
- `vec_np_opt::Vector{Int}`: Number of floors per stack
- `flag_dfl2::Bool`: DFL2 housing law compliance flag
- `sup_patio_vivienda_economica::Float64`: Economic housing patio area requirements
- `superficie_terreno::Float64`: Total terrain surface area

# Returns
- `OrderedDict`: Optimized surface areas by category and apartment distribution
"""
function opti_edificio_deptos(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, flag_dfl2, sup_patio_vivienda_economica, superficie_terreno)

    # Input validation
    validate_inputs(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, superficie_terreno)
    
    # Calculate base building geometry
    num_stacks = length(vec_ps_opt)
    basal_areas = [polyShape.polyArea(ps) for ps in vec_ps_opt]
    total_floors = sum(vec_np_opt)
    regular_floors = total_floors - 1  # Upper floors (excluding ground floor)


    # Extract apartment type specifications
    num_apartment_types = length(dict_arquitectura["vecSupUtil"])
    useful_areas = dict_arquitectura["vecSupUtil"]
    terrace_areas = dict_arquitectura["vecSupTerraza"]
    interior_areas = dict_arquitectura["vecSupInterior"]
    
    # DFL2 eligibility: apartments ≤ 140m² qualify
    dfl2_eligible = [useful_areas[i] <= 140 ? 1 : 0 for i in 1:num_apartment_types]

    # Calculate total built footprint
    total_building_area = sum(basal_areas[i] * vec_np_opt[i] for i in 1:num_stacks)

    # Initialize optimization model
    model = create_apartment_optimization_model()

    @variables(model, begin
        apartments_ground_floor[u=1:num_apartment_types] >= 0, Int
        apartments_per_upper_floor[u=1:num_apartment_types] >= 0, Int
        common_area_ground_floor >= 0
        common_area_upper_floors >= 0
        dfl2_discount >= 0
        unused_area >= 0
    end)

    # Define area expressions
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

    # Apartment count constraint
    @constraint(model, sum(apartments_ground_floor) + sum(apartments_per_upper_floor) * regular_floors == max_deptos)

    # Common area constraints
    @constraint(model, dfl2_discount <= flag_dfl2 * 0.2 * total_useful_area)
    @constraint(model, dfl2_discount <= flag_dfl2 * total_common_area)
    @constraint(model, common_area_ground_floor >= dict_arquitectura["coefSupComunPrimerPiso"] * useful_area_ground_floor)
    @constraint(model, common_area_upper_floors >= dict_arquitectura["coefSupComunPisosSup"] * useful_area_upper_floors)
    @constraint(model, total_common_area >= dict_arquitectura["coefSupComun"] * total_useful_area)
    @constraint(model, total_common_area <= 0.25 * total_useful_area)


    # Ground occupation constraints
    if sup_patio_vivienda_economica > 0
        available_ground_area = superficie_terreno - total_apartments * sup_patio_vivienda_economica
        @constraint(model, common_area_ground_floor + terrace_area_ground_floor + interior_area_ground_floor <= available_ground_area)
        @constraint(model, common_area_upper_floors + terrace_area_upper_floors + interior_area_upper_floors <= available_ground_area * regular_floors)
    else
        @constraint(model, common_area_ground_floor + terrace_area_ground_floor + interior_area_ground_floor <= basal_areas[1])
        @constraint(model, common_area_upper_floors + terrace_area_upper_floors + interior_area_upper_floors <= 
            sum(basal_areas[k] * (k==1 ? vec_np_opt[k]-1 : vec_np_opt[k]) for k=1:num_stacks))
    end

    # Buildability constraint
    @constraint(model, total_useful_area + total_common_area - dfl2_discount <= max_constructibilidad)
    
    # Total area balance
    @constraint(model, unused_area + total_common_area + total_terrace_area + total_interior_area == 
        sum(basal_areas[k] * vec_np_opt[k] for k=1:num_stacks))


    # DFL2 apartment type restrictions
    if flag_dfl2 || (sup_patio_vivienda_economica > 0)
        @constraint(model, [u=1:num_apartment_types], 
            apartments_ground_floor[u] + apartments_per_upper_floor[u] * regular_floors <= dfl2_eligible[u] * max_deptos)
    end

    # Objective: maximize useful area
    @objective(model, Max, total_useful_area)
    optimize!(model)


    # Process optimization results
    return process_optimization_results(model, 
        total_useful_area, useful_area_ground_floor, useful_area_upper_floors,
        total_common_area, common_area_ground_floor, common_area_upper_floors,
        total_terrace_area, terrace_area_ground_floor, terrace_area_upper_floors,
        total_interior_area, interior_area_ground_floor, interior_area_upper_floors,
        unused_area, dfl2_discount, total_apartments,
        apartments_ground_floor, apartments_per_upper_floor, regular_floors)
end

# Helper functions

function validate_inputs(dict_arquitectura, max_constructibilidad, max_deptos, vec_ps_opt, vec_np_opt, superficie_terreno)
    @assert haskey(dict_arquitectura, "vecSupUtil") "Architecture dictionary missing 'vecSupUtil'"
    @assert haskey(dict_arquitectura, "vecSupTerraza") "Architecture dictionary missing 'vecSupTerraza'"
    @assert haskey(dict_arquitectura, "vecSupInterior") "Architecture dictionary missing 'vecSupInterior'"
    @assert max_constructibilidad > 0 "Maximum buildability must be positive"
    @assert max_deptos > 0 "Maximum apartments must be positive"
    @assert length(vec_ps_opt) > 0 "Polygon vector cannot be empty"
    @assert length(vec_ps_opt) == length(vec_np_opt) "Polygon and floor vectors must have same length"
    @assert superficie_terreno > 0 "Terrain surface must be positive"
end

function create_apartment_optimization_model()
    model = Model(Cbc.Optimizer)
    set_optimizer_attribute(model, "ratioGap", 0.001)
    set_optimizer_attribute(model, "logLevel", 0)
    return model
end

function process_optimization_results(model, 
    total_useful_area, useful_area_ground_floor, useful_area_upper_floors,
    total_common_area, common_area_ground_floor, common_area_upper_floors,
    total_terrace_area, terrace_area_ground_floor, terrace_area_upper_floors,
    total_interior_area, interior_area_ground_floor, interior_area_upper_floors,
    unused_area, dfl2_discount, total_apartments,
    apartments_ground_floor, apartments_per_upper_floor, regular_floors)
    
    if termination_status(model) != MOI.OPTIMAL
        @warn "Optimization did not find optimal solution. Status: $(termination_status(model))"
        return create_empty_result_dict()
    end
    
    # Extract values
    results = OrderedDict(
        "supUtil" => value(total_useful_area),
        "supUtilPrimerPiso" => value(useful_area_ground_floor),
        "supUtilPisosSup" => value(useful_area_upper_floors),
        "supComun" => value(total_common_area),
        "supComunPrimerPiso" => value(common_area_ground_floor),
        "supComunPisosSup" => value(common_area_upper_floors),
        "supTerraza" => value(total_terrace_area),
        "supTerrazaPrimerPiso" => value(terrace_area_ground_floor),
        "supTerrazaPisosSup" => value(terrace_area_upper_floors),
        "supInterior" => value(total_interior_area),
        "supInteriorPrimerPiso" => value(interior_area_ground_floor),
        "supInteriorPisosSup" => value(interior_area_upper_floors),
        "descuento_dfl2" => value(dfl2_discount),
        "supNoUtilizada" => value(unused_area),
        "numDeptosTipo" => [value(apartments_ground_floor[u]) + value(apartments_per_upper_floor[u]) * regular_floors for u in axes(apartments_ground_floor, 1)],
        "numDeptos" => value(total_apartments)
    )
    
    # Display results summary
    display_optimization_summary(results)
    
    return results
end

function create_empty_result_dict()
    return OrderedDict(
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
        "numDeptosTipo" => Int[],
        "numDeptos" => 0
    )
end

function display_optimization_summary(results)
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
    println("Apartments by type: $(results["numDeptosTipo"])")
    println("=" ^ 40)
end

