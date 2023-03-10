function displayResults(resultados, dcc)
    sn = resultados.salidaNormativa
    sa = resultados.salidaArquitectonica
    si = resultados.salidaIndicadores
    st = resultados.salidaTerreno
    sm = resultados.salidaMonetaria
    so = resultados.salidaOptimizacion
    
    displayResults(sn, sa, si, st, so, sm, dcc)
end


function displayResults(sn, sa, si, st, so, sm, dcc)

    println("Características Generales de la Cabida Óptima:")
    println("----------------------------------------------")
    println("N° Deptos: ", sum(round.(sa.numDeptosTipo, digits = 2)), " (Máx. Densidad = ", round(sn.maxNumDeptos, digits = 2), ")")
    println("N° Deptos por Tipo: ", floor.(sa.numDeptosTipo[sa.numDeptosTipo .> 0.1], digits = 2)')
    println("Sup. Util por Tipo: ", floor.(dcc.supDeptoUtil[sa.numDeptosTipo .> 0.1], digits = 2)')
    println("Ocupacion: ", round(sa.ocupacion, digits = 2), " m2 (Máx. Ocupación = ", round(sn.maxOcupacion, digits = 2), " m2)")
    println("Constructibilidad: ", round(sa.constructibilidad, digits = 2), " m2 (Máx. Constructibilidad = ", round(sn.maxConstructibilidad, digits = 2), " m2)")
    println("N° Pisos: ", round(sa.numPisos, digits = 2), " (Máx. Pisos = ", round(sn.maxPisos, digits = 2), ")")
    println("Altura: ", round(sa.altura, digits = 2), " m2 (Máx. Altura = ", round(sn.maxAltura, digits = 2), " m2)")
    println("Superficie Interior: ", round(sa.superficieInterior, digits = 2), " m2")
    println("Superficie de Terrazas: ", round(sa.superficieTerraza, digits = 2), " m2")
    println("Superficie Común: ", round(sa.superficieComun, digits = 2), " m2")
    println("Superficie Edificada SNT: ", round(sa.superficieEdificadaSNT, digits = 2), " m2")
    println("Superficie por Piso: ", round(sa.superficiePorPiso, digits = 2))
    println("N° Estac. Vendibles: ", round(sa.estacionamientosVendibles, digits = 2))
    println("N° Estac. Visita: ", round(sa.estacionamientosVisita, digits = 2))
    println("N° Estac. Discapacitados: ", round(sn.minEstacionamientosDiscapacitados, digits = 2))
    println("N° Estac. Totales: ", round(sa.estacionamientosVendibles, digits = 2) + round(sa.estacionamientosVisita, digits = 2)) 
    println("N° Estac. Bicicletas: ", round(sa.numBicicleteros, digits = 2))

    println("")
    println("Análisis de Holguras:")
    println("----------------------------------------------")
    println("Rest. Coef. Ocupación: ", round(so.dualMaxOcupación, digits = 2), " m2")
    println("Rest. Constructibilidad Máxima: ", round(so.dualMaxConstructibilidad, digits = 2), " m2")
    println("Rest. Densidad Máxima: ", round(so.dualMaxDensidad, digits = 2), " unidades")

    println("")
    println("Características del Terreno:")
    println("----------------------------")
    println("Superficie Terreno: ", round(st.superficieTerreno, digits = 2), " m2")
    println("Superficie Bruta: ", round(st.superficieBruta, digits = 2), " m2")
    println("Costo Terreno: UF ", round(st.costoTerreno, digits = 2), " (", round(st.costoUnitTerreno, digits = 2), " UF/m2)")
    println("Costo Corredor: UF ", round(st.costoCorredor, digits = 2), (" (Sin IVA)"))
    println("Costo Demolición: UF ", round(st.costoDemolicion, digits = 2))
    println("Otros Costos Terreno (Inscripción, Contribuciones, etc.): UF ", round(st.otrosTerreno, digits = 2))
    println("----------------------------")
    println("Costo Total Terreno: UF ", round(st.costoTotalTerreno, digits = 2), " (", round(st.costoUnitTerrenoTotal, digits = 2), " UF/m2)")

    println("")
    println("Indicadores de Desempeño:")
    println("-------------------------")
    println("Ingresos por Ventas: UF ", round(si.ingresosVentas, digits = 2))
    println("Costo Total: UF ", round(si.costoTotal, digits = 2))
    println("Margen antes de Impuesto: UF ", round(si.margenAntesImpuesto, digits = 2))
    println("Rentabilidad Total Bruta: UF+ ", round(si.rentabilidadTotalBruta, digits = 2) * 100," %")
    println("Impuesto Renta: UF ", round(si.impuestoRenta, digits = 2))
    println("Utilidad después Impuesto: UF ", round(si.utilidadDespuesImpuesto, digits = 2))
    println("Rentabilidad Total Neta: UF+ ", round(si.rentabilidadTotalNeta, digits = 2) * 100," %")
    println("Incidencia Terreno: ", round(si.incidenciaTerreno, digits = 2))

    println("")
    println("Detalle Ingresos y Costos:")
    println("-------------------------")
    println("Ingresos Venta de Deptos: UF ", round(sm.ingresosVentaDeptos, digits = 2))
    println("----------------------------")
    println("Ingresos por Ventas: UF ", round(sm.ingresosVentas, digits = 2))
    println("                            ")
    println("Costo Total Terreno: UF ", round(sm.costoTerrenoTotal, digits = 2), " (", round(sm.costoUnitarioTerrenoTotal, digits = 2), " UF/m2)")
    println("Costo de Construcción: UF ", round(sm.costoConstruccion, digits = 2))
    println("Costo Inmobiliario: UF ", round(sm.costoInmobiliario, digits = 2))
    println("Costo de Marketing y Ventas: UF ", round(sm.costosMarketingVentas, digits = 2))
    println("Costo de Administracion: UF ", round(sm.costosAdministracion, digits = 2))
    println("Otros Costos de Ventas (Gastos Comunes, Contribuciones, Servicios) : UF ", round(sm.costosVariosVenta, digits = 2))
    println("Costo Financiero: UF ", round(sm.costosFinancieros, digits = 2))
    println("Imprevistos: UF ", round(sm.imprevistos, digits = 2))
    println("Costo Balance de Iva: UF ", round(sm.imprevistos, digits = 2))
    println("----------------------------")
    println("Costo Total: UF ", round(sm.costoTotal, digits = 2))

end
