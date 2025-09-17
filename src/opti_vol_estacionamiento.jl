function _find_optimal_offset(orig_ps::PolyShape, target_area::Float64;
                             tol::Float64=0.1, maxiter::Int=100,
                             init_bounds::Tuple{Float64,Float64}=(-100.0, 100.0))

    low, high = init_bounds
    area_low = polyShape.polyArea(polyClipper.polyOffset(orig_ps, low))
    area_high = polyShape.polyArea(polyClipper.polyOffset(orig_ps, high))

    # Auto-expand bounds if needed
    if !(area_low ≤ target_area ≤ area_high || area_high ≤ target_area ≤ area_low)
        if target_area > max(area_low, area_high)
            high *= 3
        elseif target_area < min(area_low, area_high)
            low *= 3
        end
        area_low = polyShape.polyArea(polyClipper.polyOffset(orig_ps, low))
        area_high = polyShape.polyArea(polyClipper.polyOffset(orig_ps, high))
    end

    # Ensure correct ordering
    if area_low > area_high
        low, high = high, low
    end

    best_offset = (low + high) / 2
    adaptive_tol = max(tol, target_area * 0.005)

    for i in 1:maxiter
        mid = (low + high) / 2
        area_mid = polyShape.polyArea(polyClipper.polyOffset(orig_ps, mid))
        error = abs(area_mid - target_area)

        if error ≤ adaptive_tol || abs(high - low) < 1e-8
            best_offset = mid
            break
        end

        if area_mid > target_area
            high = mid
        else
            low = mid
        end
        best_offset = mid
    end

    return polyClipper.polyOffset(orig_ps, best_offset), best_offset
end

function _create_single_level(ps_areaEst::PolyShape, areaReq::Float64)
    # Creates a single parking level with the required area.

    ps_level, _ = _find_optimal_offset(deepcopy(ps_areaEst), areaReq)
    return [ps_level], [-1]
end

function _create_multi_levels(ps_areaEst::PolyShape, areaBasalEst::Float64, 
                             areaReq::Float64, numSubtes::Int)
    # Creates multiple parking levels with optimized area distribution.

    # Calculate area for the last level
    areaLast = areaReq - (numSubtes - 1) * areaBasalEst
    
    # If last level is too small, redistribute areas equally
    if areaLast / areaBasalEst < 0.5
        uniform_area = areaReq / numSubtes
        ps_uniform, _ = _find_optimal_offset(deepcopy(ps_areaEst), uniform_area)
        vec_ps_subte = [deepcopy(ps_uniform) for _ in 1:numSubtes]
    else
        # Use standard levels with different last level
        ps_standard, _ = _find_optimal_offset(deepcopy(ps_areaEst), areaBasalEst)
        ps_last, _ = _find_optimal_offset(deepcopy(ps_areaEst), areaLast; tol=0.15, maxiter=50)
        
        vec_ps_subte = [deepcopy(ps_standard) for _ in 1:numSubtes]
        vec_ps_subte[end] = ps_last
    end
    
    # Generate level indicators (underground levels are negative)
    vec_np_subte = collect(range(-numSubtes, -1))
    
    return vec_ps_subte, vec_np_subte
end

function opti_vol_estacionamiento(ps_predio::PolyShape, ps_areaEst::PolyShape, 
                                 coefOcupacionEst::Float64, areaReq::Float64)
    # Optimizes underground parking volume distribution across multiple levels.

    # Input validation
    if coefOcupacionEst <= 0.0 || coefOcupacionEst > 1.0
        throw(ArgumentError("coefOcupacionEst must be between 0.0 and 1.0, got $coefOcupacionEst"))
    end
    if areaReq <= 0.0
        throw(ArgumentError("areaReq must be positive, got $areaReq"))
    end
    
    # Calculate area constraints
    areaPredio = polyShape.polyArea(ps_predio)
    areaEstDisponible = polyShape.polyArea(ps_areaEst)
    max_ocup = coefOcupacionEst * areaPredio
    areaBasalEst = min(areaEstDisponible, max_ocup)
    
    if isnan(areaPredio) || isnan(areaEstDisponible) || isnan(areaBasalEst)
        throw(ArgumentError("Invalid geometry: polygon area calculation returned NaN"))
    end
    
    if areaBasalEst <= 0.0
        throw(ArgumentError("No available area for parking after applying occupancy constraints"))
    end
    
    # Calculate number of required levels
    ratio = areaReq / areaBasalEst
    if isnan(ratio) || isinf(ratio)
        throw(ArgumentError("Invalid area ratio: areaReq=$areaReq, areaBasalEst=$areaBasalEst"))
    end
    numSubtes = ceil(Int, ratio)
    
    if numSubtes == 1
        # Single level case
        return _create_single_level(ps_areaEst, areaReq)
    else
        # Multi-level case  
        return _create_multi_levels(ps_areaEst, areaBasalEst, areaReq, numSubtes)
    end
end
