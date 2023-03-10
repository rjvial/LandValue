using LandValue, JLD2

fpe = FlagPlotEdif3D(true,  # predio
                     true,  # volTeor
                     true,  # restSombra
                     true,  # edif
                     true,  # sombraVolTeor_p
                     true,  # sombraVolTeor_o
                     true,  # sombraVolTeor_s
                     true,  # sombraEdif_p
                     true,  # sombraEdif_o
                     true)  # sombraEdif_s


dcn = datosCabidaNormativa(5, # SEPMIN (m): max(4, separación mínima deslindes) OGUC 2.6.3
                     5, # ANTEJARDIN (m) 
                     2.75, # RASANTE (m de altura / m de separación)
                     60, # 24, #ALTURAMAX (m)
                     30, # 9, #MAXPISOS (unidades)
                     .7, # COEFOCUPACION (m2 / m2 de terreno)
                     1000, # SUBPREDIALMIN (m2)
                     2500, # DENSIDADMAX (Habitantes / 10000 m2 de terreno bruto)
                     true, # FLAGDENSIDADBRUTA
                     4, # COEFCONSTRUCTIBILIDAD (m2 / m2 de terreno)
                     [.5, 1, 1, 1], # ESTACIONAMIENTOSPORVIV (unidades / departamento)
                     .15, # PORCADICESTACVISITAS (unidades / estacionamiento vendible)
                     34, # SUPPORESTACIONAMIENTO (m2 / Estacionamiento)
                     .5, # ESTBICICLETAPORVIV (unidades / estacionamientos totales)
                     3, # BICICLETASPOREST 
                     true, # FLAGCAMBIOESTPORBICICLETA
                     10, # MAXSUBTE (unidades)
                     .8, # COEFOCUPACIONEST (m2 / superficieTerreno)
                     7, # SEPESTMIN (m)
                     0 # REDUCCIONESTPORDISTMETRO
                     );
     
dca = datosCabidaArquitectura(2.55, # 2.625, # ALTURAPISO (m / piso)
                         .2, # PORCSUPCOMUN (m2 / m2 útil)
                         .05, # PORCTERRAZA (m2 / m2 útil)
                         15,#12, # ANCHOMAX (m) 
                         [], 
                         []
                         );
                          
dcc = datosCabidaComercial([20, 30, 38, 45], # SUPDEPTOUTIL (m2)
                     [.3, .4, .4, 1], # MAXPORCTIPODEPTO  
                     [56, 55, 54, 52], # PRECIOVENTA (UF / m2 vendible) 
                     200 # PRECIOVENTAEST (UF / unidad)
                     );
     
dcu = datosCabidaUnit(30, # duracionProyecto 
             20, # CostoTerreno 
             2 * 1.19 / 100, # ComisionCorredor 
             0.60, # Demolicion 
             20, # LosaSNT 
             10, # LosaBNT 
             5, # EstacVisita 
             3 / 100, # ExtrasPostVenta 
             1.75 / 100, # Arquitectura 
             2.75 / 100, # GestionAdministracion 
             30, # ITO 
             30, # Contabilidad
             0.85 / 100, # Legales 
             0.145, # Calculo 
             250, # MecanicaSuelo 
             50, # Topografia 
             .45 / 100, # ProyectoElectrico 
             0, # ProyectoSanitario 
             0, # ProyectoSeguridad 
             50, # ProyectoPavimentacion 
             25, # ProyectoBasura 
             0, # ProyectoCalefaccion 
             1.2 / 100, # Marketing 
             0.5 / 100, # PilotSalaVentas 
             0, # NotarialesLegales 
             0, # CBR
             0, # EmpalmesAportes 
             600, # DerechosPermisosMunicipales 
             15, # InspeccionCertificacionTecnica 
             0, # Contribuciones 
             120, # CopiaPlanosArquitectura 
             60, # CopiaPlanosObra 
             300, # HallAcceso 
             400, # JardinesPaisajismo 
             0, # HabilitacionSalaUsosMultiples 
             0, # HabilitacionPiscinaEnfermeria 
             0, # CuentasServiciosDeptos 
             0, # GastosComunes 
             0, # ContribucionesDeptos 
             0, # Seguros 
             1 / 100, # ResponsabilidadCivil 
             1 / 100, # PostVentaInmobiliaria 
             0.1 / 100, # SeguroVentaEnVerde 
             1 / 100 # Imprevistos
             );
             
dcf = datosCabidaFlujo([0.05, 0.05, 0.05, 0.05, 0.10, 0.70], # IngresosVentas
             [1, 0, 0, 0, 0, 0], # CostoTerreno
             [0.05, 0.10, 0.35, 0.35, .15, 0], # CostoConstruccion
             [0.40, 0.15, 0.15, 0.15, .15, 0], # CostoHonorariosProyectos
             [0, 0.10, 0.20, 0.20, 0.25, 0.25], # CostoVenta
             [0.1, 0.40, 0.25, 0.15, 0.05, 0.05], # CostoInmobiliarioObra
             [0, 0, 0, 0, 0.50, 0.50], # CostosHabilitacion
             [0, 0, 0, 0, 0.25, 0.75], # CostosPuestaEnMarcha
             [0.05, 0.05, 0.05, 0.05, 0.05, 0.75], # CostosAtencionCliente
             [0, 0.20, 0.20, 0.20, 0.20, 0.20], # Imprevistos
             [0.05, 0.10, 0.35, 0.35, .15, 0], # ingresoLineaCredito
             [0, 0, 0.10, 0.35, 0.35, .2], # pagoLineaCredito
             .27, # TasaImpuestoRenta
             .05, # TasaInteresLineaCredito 
             0.8 * dcu.duracionProyecto, # DuracionLineaCredito 
             15 # Tasaciones
             );
     
dcr = datosCabidaRentabilidad(1.20) # RetornoExigido


@save "defaults.jld2" fpe dcn dca dcc dcu dcf dcr
