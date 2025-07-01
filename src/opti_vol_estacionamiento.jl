function opti_vol_estacionamiento(ps_predio, ps_areaEst, numEst, numBodegas, dcn)
    # –––––––––– helper to find the right offset via bisection ––––––––––
    function find_offset(orig_ps, target_area, tol, maxiter;
                         init_low = -100.0, init_high = 100.0)
        low, high = init_low, init_high
        area_low  = polyShape.polyArea(polyShape.polyOffset(orig_ps, low))
        area_high = polyShape.polyArea(polyShape.polyOffset(orig_ps, high))
        @assert area_low < target_area < area_high "Cannot bracket target area; adjust init_low/init_high"

        best_d = 0.0
        for _ in 1:maxiter
            mid = (low + high) / 2
            area_mid = polyShape.polyArea(polyShape.polyOffset(orig_ps, mid))
            err = area_mid - target_area

            if abs(err) ≤ tol
                best_d = mid
                break
            elseif err > 0
                high = mid
            else
                low = mid
            end

            best_d = mid
        end

        (polyShape.polyOffset(orig_ps, best_d), best_d)
    end

    # –––––––––– 1) base‐parcel offset ––––––––––
    areaPredio     = polyShape.polyArea(ps_predio)
    max_ocup       = dcn.coefOcupacionEst * areaPredio
    areaBasalEst   = min(polyShape.polyArea(ps_areaEst), max_ocup)

    tol_base, iter_base = 0.1, 100
    ps_baseSubte, _ = find_offset(deepcopy(ps_areaEst), areaBasalEst, tol_base, iter_base)
    areaActualBase = polyShape.polyArea(ps_baseSubte)

    # –––––––––– 2) compute how many tiles & last‐tile target area ––––––––––
    areaReq       = numEst*dcn.supPorEstacionamiento + numBodegas*dcn.supPorBodega

    numSubtes     = ceil(Int, areaReq / areaActualBase)
    areaLast      = areaReq - (numSubtes - 1)*areaActualBase
    if areaLast/areaActualBase < 0.5
        areaLast = areaReq/numSubtes
        tol_base, iter_base = 0.1, 100
        ps_baseSubte, _ = find_offset(deepcopy(ps_areaEst), areaLast, tol_base, iter_base)
    end


    # –––––––––– 3) build vector of sub‐polygons ––––––––––
    vec_ps_subte = [ps_baseSubte for _ in 1:numSubtes]
    tol_last, iter_last = 0.15, 50
    ps_ultSubte, _ = find_offset(deepcopy(ps_areaEst), areaLast, tol_last, iter_last)
    vec_ps_subte[end] = ps_ultSubte

    # –––––––––– 4) indices for optimization ––––––––––
    vec_np_subte = [-(numSubtes - 1), -1]

    return vec_ps_subte, vec_np_subte
end