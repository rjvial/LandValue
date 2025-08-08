"""
    opti_vol_estacionamiento(ps_predio::PolyShape, ps_areaEst::PolyShape, coefOcupacionEst::Float64, areaReq::Float64)

Optimizes underground parking volume distribution across multiple levels.

# Arguments
- `ps_predio::PolyShape`: Property boundary polygon
- `ps_areaEst::PolyShape`: Available parking area polygon
- `coefOcupacionEst::Float64`: Parking occupancy coefficient (0.0-1.0)
- `areaReq::Float64`: Total required parking area (m²)

# Returns
- `vec_ps_subte::Vector{PolyShape}`: Vector of parking level polygons
- `vec_np_subte::Vector{Int}`: Vector of level indicators (negative for underground)

# Throws
- `ArgumentError`: If inputs are invalid or target area cannot be achieved
"""
function opti_vol_estacionamiento(ps_predio::PolyShape, ps_areaEst::PolyShape, 
                                 coefOcupacionEst::Float64, areaReq::Float64)
    
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
    
    if areaBasalEst <= 0.0
        throw(ArgumentError("No available area for parking after applying occupancy constraints"))
    end
    
    # Calculate number of required levels
    numSubtes = ceil(Int, areaReq / areaBasalEst)
    
    if numSubtes == 1
        # Single level case
        return _create_single_level(ps_areaEst, areaReq)
    else
        # Multi-level case  
        return _create_multi_levels(ps_areaEst, areaBasalEst, areaReq, numSubtes)
    end
end

"""
    _find_optimal_offset(orig_ps::PolyShape, target_area::Float64; 
                        tol::Float64=0.1, maxiter::Int=100, 
                        init_bounds::Tuple{Float64,Float64}=(-100.0, 100.0))

Finds the optimal polygon offset to achieve target area using bisection method.
"""
function _find_optimal_offset(orig_ps::PolyShape, target_area::Float64; 
                             tol::Float64=0.1, maxiter::Int=100, 
                             init_bounds::Tuple{Float64,Float64}=(-100.0, 100.0))
    
    low, high = init_bounds
    
    # Validate bounds can bracket the target
    area_low = polyShape.polyArea(polyClipper.polyOffset(orig_ps, low))
    area_high = polyShape.polyArea(polyClipper.polyOffset(orig_ps, high))
    
    if !(area_low < target_area < area_high)
        throw(ArgumentError("Cannot bracket target area $target_area. Got bounds: [$area_low, $area_high]. Adjust init_bounds."))
    end
    
    best_offset = 0.0
    converged = false
    
    for i in 1:maxiter
        mid = (low + high) / 2
        area_mid = polyShape.polyArea(polyClipper.polyOffset(orig_ps, mid))
        error = area_mid - target_area
        
        if abs(error) ≤ tol
            best_offset = mid
            converged = true
            break
        elseif error > 0
            high = mid
        else
            low = mid
        end
        
        best_offset = mid
    end
    
    if !converged
        @warn "Bisection did not converge after $maxiter iterations. Final error: $(abs(polyShape.polyArea(polyClipper.polyOffset(orig_ps, best_offset)) - target_area))"
    end
    
    return polyClipper.polyOffset(orig_ps, best_offset), best_offset
end

"""
    _create_single_level(ps_areaEst::PolyShape, areaReq::Float64)

Creates a single parking level with the required area.
"""
function _create_single_level(ps_areaEst::PolyShape, areaReq::Float64)
    ps_level, _ = _find_optimal_offset(deepcopy(ps_areaEst), areaReq)
    return [ps_level], [-1]
end

"""
    _create_multi_levels(ps_areaEst::PolyShape, areaBasalEst::Float64, 
                        areaReq::Float64, numSubtes::Int)

Creates multiple parking levels with optimized area distribution.
"""
function _create_multi_levels(ps_areaEst::PolyShape, areaBasalEst::Float64, 
                             areaReq::Float64, numSubtes::Int)
    
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