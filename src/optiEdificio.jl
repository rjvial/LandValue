function optiEdificio(dcn, dca, dcp, dcc, dcu, dcr, mat_dcn_opt, alturaEdif, ps_base, superficieTerreno, superficieTerrenoBruta, sup_areaEdif)

    areaBasalPso = polyShape.polyArea(ps_base)
    numTiposDepto = length(dcc.supDeptoUtil);

    flag_viv_eco_opt = mat_dcn_opt[1]

    # superficieDensidad = dcn.flagDensidadBruta ? superficieTerrenoBruta : superficieTerreno
    # maxDeptos = dcn.densidadMax / 4 * superficieDensidad / 10000;
    maxDeptos = mat_dcn_opt[2]

    # maxOcupación = dcn.coefOcupacion > 0 ? dcn.coefOcupacion * superficieTerreno : sup_areaEdif
    maxOcupación = mat_dcn_opt[3]

    # maxSupConstruida = dcn.coefConstructibilidad > 0 ? superficieTerreno * dcn.coefConstructibilidad * (1 + 0.3 * dcp.fusionTerrenos) : dcn.maxPisos[1] * sup_areaEdif
    maxSupConstruida = mat_dcn_opt[4]

    # numPisosMaxVol = Int(round(alturaEdif / dca.alturaPiso))
    numPisosMaxVol = mat_dcn_opt[5]


    maxOcupación, maxSupConstruida, maxDeptos
    ##############################################
    # PARTE "3": DEFINICIÓN SOLVER               #
    ##############################################

    # m = JuMP.Model(GLPK.Optimizer)
    m = JuMP.Model(Cbc.Optimizer)
    JuMP.set_optimizer_attribute(m, "ratioGap", 0.001)
    set_optimizer_attribute(m, "logLevel", 0)
#    set_optimizer_attribute(m, "threads", 3)
    

    ##############################################
    # PARTE "4": VARIABLES DE DECISION           #
    ##############################################

    @variables(m, begin
        numPisos == numPisosMaxVol, Int
        0 <= numDeptosTipo[u = 1:numTiposDepto], Int # Toma valores enteros
        0 <= numDeptosTipoPorPiso[u = 1:numTiposDepto], Int # Toma valores enteros
        tipoDepto[u = 1:numTiposDepto], Bin # Es 1 si el tipoDepto se utiliza, 0 en caso contrario 
        0 <= CostoUnitTerreno
        0 <= superficieUtil
        0 <= superficieComun
        0 <= estacionamientosVendibles
        0 <= maxSupTipo
    end)



    ##############################################
    # PARTE "5": EXPRESIONES AUXILIARES          #
    ##############################################

    # Cálculo Número de Estacionamientos
    estacionamientosViviendas = sum(dcn.estacionamientosPorViv .* numDeptosTipo) 
    estacionamientosVisitas = estacionamientosViviendas * dcn.porcAdicEstacVisitas;
    estacionamientosNormales = estacionamientosViviendas + estacionamientosVisitas
    estacionamientosDiscapacitados =  (maxDeptos <= 20) ? 1 : 
                                     ((maxDeptos <= 50) ? 2 : 
                                     ((maxDeptos <= 200) ? 3 : 
                                     ((maxDeptos <= 400) ? 4 : 
                                     ((maxDeptos <= 500) ? 5 : (0.01*maxDeptos)))))
    estacionamientosBicicletasAntes = estacionamientosNormales * dcn.estBicicletaPorEst;
    descuentoEstBicicletas = estacionamientosBicicletasAntes/dcn.bicicletasPorEst
    descuentoEstCercaniaMetro = 0*estacionamientosNormales * 0.5*dcn.reduccionEstPorDistMetro
    cambioEstBicicletas = 0*dcn.flagCambioEstPorBicicleta * estacionamientosNormales / 3
    estacionamientosNormalesDespDesc = estacionamientosNormales - descuentoEstCercaniaMetro - descuentoEstBicicletas - cambioEstBicicletas    
    estacionamientosBicicletas = estacionamientosBicicletasAntes + (descuentoEstBicicletas + cambioEstBicicletas) * dcn.bicicletasPorEst
  
    # Cálculo Número de Bodegas
    bodegas = sum(numDeptosTipo .* dcc.bodegasPorViv)  # Uno bodega por departamento

    # Cálculo de Superficies
    superficieUtilDepto = numDeptosTipo .* dcc.supDeptoUtil;
    superficieUtil = sum(superficieUtilDepto); # = superficieVendible;  Incluye terrazas como medias superficies
    superficieTerrazaDepto = numDeptosTipo .* dcc.supTerraza;
    superficieTerraza = sum(superficieTerrazaDepto);
    superficieInteriorDepto = numDeptosTipo .* dcc.supInterior;
    superficieInterior = sum(superficieInteriorDepto);
    superficiePrimerPiso = min(areaBasalPso, maxOcupación)
    superficieLosaSNT = areaBasalPso*(numPisos-1) + superficiePrimerPiso    
    superficieComun = superficieLosaSNT - (superficieTerraza + superficieInterior) # Superficie Común absorbe lo que no se utiliza en departamentos 
    superficieEstacionamientos = dcn.supPorEstacionamiento * estacionamientosVendibles
    superficieBodegas = dcn.supPorBodega * bodegas
    superficieLosaBNT = superficieEstacionamientos + superficieBodegas;
    superficieConstruida = superficieLosaSNT + superficieLosaBNT

    # Cálculo Costos de Terreno
    CostoTerreno = CostoUnitTerreno * superficieTerreno
    CostoCorredorTerreno = CostoTerreno * dcu.comisionCorredor
    CostoDemolicion = dcu.demolicion * superficieTerreno
    OtrosTerreno = dcu.otrosTerreno * CostoTerreno
    CostoTerrenoTotal = CostoTerreno + CostoCorredorTerreno + CostoDemolicion + OtrosTerreno
    
    # Cálculo de Ingresos por Ventas
    ingresosVentaDeptos = sum(numDeptosTipo .* dcc.Precio_Estimado);
    IngresosVentas = ingresosVentaDeptos;
    IvaVentas = (IngresosVentas/1.19 - CostoTerreno)*.19 


    # Cálculo Costos de Construcción
    CostoConstruccionSNT = dcu.losaSNT * superficieLosaSNT # Costos sin IVA
    CostoConstruccionBNT = dcu.losaBNT * superficieLosaBNT # Costos sin IVA
    CostoInspeccion = dcu.ito * dcu.duracionProyecto
    CostoConstruccionAntesIva = CostoConstruccionSNT + CostoConstruccionBNT + CostoInspeccion
    IvaConstruccion = CostoConstruccionAntesIva * dcu.ivaConstruccion
    CreditoIvaConstruccion = CostoConstruccionAntesIva * dcu.creditoIvaConstruccion * 0
    CostoConstruccion = CostoConstruccionAntesIva + IvaConstruccion - CreditoIvaConstruccion

    # Balance Iva 
    BalanceIva = IvaVentas - IvaConstruccion
    
    # Cálculo Costo Inmobiliario
    CostoArquitectura = dcu.arquitectura * superficieUtil
    CostoIngenieria = dcu.calculo * superficieConstruida + (dcu.mecanicaSuelo + dcu.topografia) * superficieTerreno
    CostosProyectosEspecialidad = dcu.proyectosEspecialidades * superficieConstruida
    CostoEmpalmesAporteMitigaciones = dcu.empalmes * sum(numDeptosTipo) + dcu.aportesUrbanos * 0 + dcu.mitigacionesViales * 0
    CostoPermisosMunicipales = dcu.derechosPermisosMunicipales
    CostoInmobiliario = CostoArquitectura + CostoIngenieria + CostosProyectosEspecialidad + CostoEmpalmesAporteMitigaciones + CostoPermisosMunicipales

    # Cálculo Costo de Venta
    CostosMarketingVentas = dcu.marketing * IngresosVentas + dcu.habilitacionSalaVentaComunes
    
    # Cálculo Costos de Administración
    CostosAdministracion = dcu.gestionAdministracion * IngresosVentas + dcu.contabilidad * dcu.duracionProyecto + dcu.legales * IngresosVentas
    
    # Cálculo Costos Varios de Venta
    CostosVariosVenta = dcu.seguros * IngresosVentas + dcu.postVentaInmobiliaria * IngresosVentas + dcu.seguroVentaEnVerde * IngresosVentas + dcu.variosVentas * IngresosVentas
    
    # Cálculo Costos Financieros
    CostosFinancieros = dcu.costoFinanciero * CostoConstruccionAntesIva

    # Cálculo de Otros Costos
    Imprevistos = dcu.imprevistos * IngresosVentas
    
    # Cálculo Costo Total
    CostoTotal = CostoTerrenoTotal + CostoConstruccion + CostoInmobiliario + CostosMarketingVentas + CostosAdministracion +
            CostosVariosVenta + 
            CostosFinancieros + 
            Imprevistos + 
            BalanceIva


    flag_tipoDepto = [1 for i = 1:numTiposDepto]
    if dcn.coefConstructibilidad <= 0
        flag_tipoDepto[dcc.supDeptoUtil .>= 140] .= 0
    end        
    ##############################################
    # PARTE "6": RESTRICCIONES DEL MIP           #
    ##############################################

    @constraints(m, begin
    # Restricción de Superficie Común
        superficieComun >= superficieUtil * dca.porcSupComun     
  
    # Restricción de Rentabilidad Mínima
        IngresosVentas >= dcr.retornoExigido * CostoTotal

    # Restricción de Densidad
        sum(numDeptosTipo) <= maxDeptos

    # Restricciones de Asignacion de Tipos de Deptos desde Piso 2 al N
        numDeptosTipoPorPiso .* (numPisosMaxVol - 1) .== numDeptosTipo

    # Restricciones de Estacionamientos
        estacionamientosVendibles >= sum(dcc.estacionamientosPorViv .* numDeptosTipo)  
        estacionamientosVendibles >= estacionamientosNormalesDespDesc - estacionamientosVisitas

    # Restricciones para Controlar Dispersión entre la Superficie del Tipo más Chico y el más Grande
        tipoDepto .* dcc.supDeptoUtil .<= ones(numTiposDepto) .* flag_tipoDepto * maxSupTipo
        tipoDepto .* dcc.supDeptoUtil .* 2.5 + (ones(numTiposDepto) - tipoDepto)*100000 .>= ones(numTiposDepto) * maxSupTipo
        tipoDepto .<= numDeptosTipo
        numDeptosTipo .<= 10000*tipoDepto
    end)

    ##############################################
    # PARTE "7": FUNCIÓN OBJETIVO Y EJECUCIÓN    #
    ##############################################

    @objective(m, Max, CostoUnitTerreno )
    # @objective(m, Max, sum(numDeptosTipo))
    # @objective(m, Max, IngresosVentas-CostoTotal)

    # Resuelve el problema de optimización
    JuMP.optimize!(m)

    if termination_status(m) == MOI.OPTIMAL
        status = true

    ##############################################
    # PARTE "8": PRESENTACION DE RESULTADOS      #
    ##############################################

        # Construye estructura con los resultados de la optimización   
        sn = SalidaNormativa(
            maxDeptos, # maxNumDeptos
            maxOcupación, # maxOcupacion
            maxSupConstruida, # maxConstructibilidad
            dcn.maxPisos[1], # maxPisos
            dcn.alturaMax[1], # maxAltura
            JuMP.value(estacionamientosVendibles), # minEstacionamientosVendible
            JuMP.value(estacionamientosVisitas), # minEstacionamientosVisita
            estacionamientosDiscapacitados # minEstacionamientosDiscapacitados
        )

        sa = SalidaArquitectonica(
            JuMP.value.(numDeptosTipo), # numDeptosTipo
            sum(JuMP.value.(numDeptosTipo)), # numDeptos
            min(areaBasalPso, maxOcupación), # ocupacion
            JuMP.value(superficieUtil), # constructibilidad
            JuMP.value(numPisos), # numPisos
            JuMP.value(numPisos)*dca.alturaPiso, # altura
            JuMP.value(superficieInterior), # superficieInterior
            JuMP.value(superficieTerraza), # superficieTerraza
            JuMP.value(superficieComun), # superficieComun
            JuMP.value(superficieComun)+JuMP.value(superficieTerraza)+JuMP.value(superficieInterior), # superficieEdificadaSNT
            areaBasalPso, # superficiePorPiso
            JuMP.value(estacionamientosVendibles), # estacionamientosVendibles
            JuMP.value(estacionamientosVisitas), # estacionamientosVisita
            JuMP.value(estacionamientosVendibles) + JuMP.value(estacionamientosVisitas), # numEstacionamientos Totales
            JuMP.value(estacionamientosBicicletas), # numBicicleteros
            JuMP.value(bodegas) # numBodegas
            )

        si = SalidaIndicadores( 
            JuMP.value(IngresosVentas), # IngresosVentas
            JuMP.value(CostoTotal), # CostoTotal
            JuMP.value(IngresosVentas) - JuMP.value(CostoTotal), # MargenAntesImpuesto
            0.27 * (JuMP.value(IngresosVentas) - JuMP.value(CostoTotal)), # ImpuestoRenta
            JuMP.value(IngresosVentas) - JuMP.value(CostoTotal) - 0.27 * (JuMP.value(IngresosVentas) - JuMP.value(CostoTotal)), # UtilidadDespuesImpuesto
            (JuMP.value(IngresosVentas) - JuMP.value(CostoTotal)) / JuMP.value(CostoTotal), # RentabilidadTotalBruta
            (JuMP.value(IngresosVentas) - JuMP.value(CostoTotal) - 0.27 * (JuMP.value(IngresosVentas) - JuMP.value(CostoTotal))) / JuMP.value(CostoTotal), # RentabilidadTotalNeta
            JuMP.value(CostoTerrenoTotal) / JuMP.value(IngresosVentas), # IncidenciaTerreno
        )

        st = SalidaTerreno( 
            superficieTerreno, # superficieTerreno
            superficieTerrenoBruta, # superficieBruta
            JuMP.value(CostoTerreno), # costoTerrenoAntesCorr
            JuMP.value(CostoUnitTerreno), # costoUnitTerreno
            JuMP.value(CostoCorredorTerreno), # costoCorredor
            JuMP.value(CostoDemolicion), # costoDemolicion
            JuMP.value(OtrosTerreno), # otrosTerreno
            JuMP.value(CostoTerrenoTotal), # costoTerreno
            JuMP.value(CostoTerrenoTotal) / superficieTerreno # costoUnitTerrenoTotal
        )

        so = SalidaOptimizacion(
            maxOcupación - JuMP.value(superficiePrimerPiso),
            maxSupConstruida - JuMP.value(superficieUtil), # Holgura Constructibilidad
            maxDeptos - sum(JuMP.value.(numDeptosTipo)), # Holgura Densidad
        )

        sm = SalidaMonetaria( 
            JuMP.value(ingresosVentaDeptos), # ingresosVentaDeptos
            JuMP.value(IngresosVentas), # ingresosVentas
            JuMP.value(CostoTerrenoTotal), # costoTerrenoTotal
            JuMP.value(CostoTerrenoTotal) / superficieTerreno, # costoUnitarioTerreno
            JuMP.value(CostoConstruccion), # costoConstruccion
            JuMP.value(BalanceIva), # balanceIva
            JuMP.value(CostoInmobiliario), # costoInmobiliario
            JuMP.value(CostosMarketingVentas), # costosMarketingVentas
            JuMP.value(CostosAdministracion), # costosAdministracion
            JuMP.value(CostosVariosVenta), # costosVariosVenta
            JuMP.value(CostosFinancieros), # costosFinancieros
            JuMP.value(Imprevistos), # imprevistos
            JuMP.value(CostoTotal) # costoTotal
            )


    else
        status = false
        sn = nothing
        sa = nothing
        si = nothing
        st = nothing
        so = nothing
        sm = nothing
    end

    display("AreaEdif = " * string(areaBasalPso*JuMP.value(numPisos)))
    display("SupComun = " * string(JuMP.value(superficieComun)))
    display("SupTerraza = " * string(JuMP.value(superficieTerraza)))
    display("SupInterior = " * string(JuMP.value(superficieInterior)))
    display("Total = " * string(JuMP.value(superficieComun)+JuMP.value(superficieTerraza)+JuMP.value(superficieInterior)))
    display("SupUtil = " * string(JuMP.value(superficieUtil)))

    return sn, sa, si, st, so, sm, status  

end