using LandValue

conn_LandValue = pg_julia.connection("LandValue", "postgres", "postgres")

pg_julia.deleteTable(conn_LandValue, "tabla_costosunitarios_default")

query_str = """ 
CREATE TABLE public.tabla_costosunitarios_default
(
    "duracionProyecto" double precision,
    "costoTerreno" double precision,
    "comisionCorredor" double precision,
    "demolicion" double precision,
    "otrosTerreno" double precision,
    "losaSNT" double precision,
    "losaBNT" double precision,
    "ito" double precision,
    "ivaConstruccion" double precision,
    "creditoIvaConstruccion" double precision,
    "arquitectura" double precision,
    "calculo" double precision,
    "mecanicaSuelo" double precision,
    "topografia" double precision,
    "proyectosEspecialidades" double precision,
    "empalmes" double precision,
    "aportesUrbanos" double precision,
    "mitigacionesViales" double precision,
    "derechosPermisosMunicipales" double precision,
    "marketing" double precision,
    "habilitacionSalaVentaComunes" double precision,
    "gestionAdministracion" double precision,
    "contabilidad" double precision,
    "legales" double precision,
    "seguros" double precision,
    "postVentaInmobiliaria" double precision,
    "seguroVentaEnVerde" double precision,
    "variosVentas" double precision,
    "costoFinanciero" double precision,
    "imprevistos" double precision,
    id bigint NOT NULL,
    CONSTRAINT tabla_costosunitarios_default_pkey PRIMARY KEY (id)
)
"""

pg_julia.query(conn_LandValue, query_str)

vecColumnNames = ["duracionProyecto",
"costoTerreno",
"comisionCorredor",
"demolicion",
"otrosTerreno",
"losaSNT",
"losaBNT",
"ito",
"ivaConstruccion",
"creditoIvaConstruccion",
"arquitectura",
"calculo",
"mecanicaSuelo",
"topografia",
"proyectosEspecialidades",
"empalmes",
"aportesUrbanos",
"mitigacionesViales",
"derechosPermisosMunicipales",
"marketing",
"habilitacionSalaVentaComunes",
"gestionAdministracion",
"contabilidad",
"legales",
"seguros",
"postVentaInmobiliaria",
"seguroVentaEnVerde",
"variosVentas",
"costoFinanciero",
"imprevistos",
"id"
]
vecColumnValue = ["24",
"40", # UF/m2
"0.02", # UF/UF CostoTerreno
"0.6", # UF/m2 Terreno
"0.003", # UF/UF CostoTerreno
"21", # UF/m2 SNT
"13", # UF/m2 BNT
"100", # UF/duracionProyecto
"0.19", # UF/UF CostoConstruccionAntesIva
"0.065", # UF/UF CostoConstruccionAntesIva
"0.4", # UF/m2 útiles
"0.145", # UF/m2 const
"0.0020", # UF/m2 terreno
"0.0080", # UF/m2 terreno
"0.31", # UF/m2 const
"50", # UF/vivienda
"0",
"0",
"0",
"0.025", # UF/UF venta
"1000", # UF
"0.05", # UF/UF venta
"12", # UF/duracionProyecto
"0.004", # UF/UF venta
"0",
"0.02", # UF/UF const
"0.001", # UF/UF venta
"0.001", # UF/UF venta
"0.034", # * costosConstruccion
"0.03", # * costosConstruccion
"1"
]

pg_julia.insertRow!(conn_LandValue, "tabla_costosunitarios_default", vecColumnNames, vecColumnValue, :id)
