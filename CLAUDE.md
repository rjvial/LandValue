# LandValue - Claude Code Memory

## Project Overview
LandValue is a Julia-based real estate development optimization system for the Chilean market. It performs land value analysis, building volumetric optimization, and generates 3D building models while ensuring compliance with Chilean urban development regulations. Integrates with Neo4j for property data and AWS for cloud infrastructure.

## Key Domain Concepts
- **Predios**: Individual land parcels with geometric properties and legal constraints
- **Combis**: Strategic land combinations optimized for development potential
- **Volumetric Optimization**: 3D building volume optimization considering shadows, setbacks, and regulations
- **Cabida**: Development feasibility analysis (architectural, commercial, financial)
- **Normativa**: Chilean urban planning regulations and building codes

## Architecture & Module Structure

### Main Module: `src/LandValue.jl`
- Defines core geometric data structures: `PolyShape`, `LineShape`, `PointShape`
- Implements geometric operator overloading (+, -, *) for shape objects
- Contains development data structures: `DatosCabidaPredio`, `DatosCabidaArquitectura`, etc.
- Includes modules: `polyShape.jl`, `polyPlot.jl`, `polyGdal.jl`, `polyClipper.jl`

## 🔴 CRITICAL: Module Usage Rules 🔴

### **Module Hierarchy (Use Exactly As Specified):**

#### 1. **polyShape** - Core Geometric Operations
```julia
ps = polyShape.polyBox(x, y, width, height, angle)
area = polyShape.polyArea(ps)
ps_union = polyShape.polyUnion(ps1, ps2)
```
**Functions**: `polyBox`, `polyRotate`, `polyArea`, `polyUnion`, `polyDifference`, `polyIntersect`, `subShape`, `numVertices`, etc.

#### 2. **polyGdal** - GDAL Integration  
```julia
ps = polyGdal.astext2polyshape(wkt_string)
geom = polyGdal.shape2geom(ps)
buffered = polyGdal.shapeBuffer(ps, distance, segments)
```
**Functions**: `astext2polyshape`, `shape2geom`, `geom2shape`, `shapeBuffer`, `shapeArea`, `shapeCentroid`, `shapeHull`, etc.

#### 3. **polyClipper** - Clipper Library Operations
```julia
offset_poly = polyClipper.polyOffset(ps, distance)
clipper_path = polyClipper.shape2clipper(ps)
```
**Functions**: `polyOffset`, `shape2clipper`, `clipper2shape`, `clipper_union`, `clipper_difference`, `clipper_intersection`, etc.

#### 4. **polyPlot** - Visualization
```julia
fig, ax = polyPlot.plotPolyshape2D(ps, color="blue")
fig, ax = polyPlot.plotPolyshape3D(ps, height=10.0)
```
**Functions**: `plotPolyshape2D`, `plotPolyshape3D`, `plotPolyshape2Din3D`, `plotPolyshape2DVecin3D`

### **❌ Critical Prohibitions:**
- Never use `polyShape.shapeBuffer()` → Use `polyGdal.shapeBuffer()`
- Never use `polyShape.polyOffset()` → Use `polyClipper.polyOffset()`
- Never use `polyShape.astext2polyshape()` → Use `polyGdal.astext2polyshape()`

## Key Dependencies
- **Optimization**: JuMP, Cbc, Ipopt, BlackBoxOptim, NOMAD, SCIP
- **Geometry**: ArchGDAL, Clipper, LazySets, Proj  
- **Database**: LibPQ (PostgreSQL), custom Neo4j SSH integration
- **Cloud**: AWS SDK, AWSS3
- **Visualization**: PyPlot, PyCall
- **Data**: DataFrames, CSV, JSON3, XLSX

## Core Scripts & Modules

### Key Scripts
- `script_0_prediosEstrategicos.jl`: Strategic property identification via Neo4j
- `script_0_segmentoCalles.jl`: Street segment analysis
- `script_2A_optim_volumetrica_indiv.jl`: Individual volumetric optimization
- `script_4_generaImagenesCabida.jl`: Development capacity visualizations
- `script_6_generaCodigoScr.jl`: SCR code generation
- `script_8_generaGeojson.jl`: GeoJSON export

### Optimization Modules
- `opti_edificio*.jl`: Building optimization algorithms
- `optimal_pricing.jl`, `optimal_lot_selection.jl`: Economic optimization
- `quad_opti_*.jl`: Quadratic optimization utilities

### Geometric Processing
- `generaSombra*.jl`: Shadow generation and analysis
- `generaVol3D.jl`: 3D volume generation
- `generaPoligonoCorte.jl`: Polygon cutting operations

### Database Integration
- `neo4j_julia.jl`: Neo4j operations via SSH tunneling
- `pg_julia.jl`: PostgreSQL connection and queries
- `aws_julia.jl`: AWS EC2 and S3 operations
- `obtiene_*.jl`: Data retrieval functions

## Development Patterns
- **No inline comments**: Self-documenting code via descriptive function names
- **Mutable structs**: Extensive use for geometric and data containers
- **Module separation**: Strict boundaries between polyShape/polyGdal/polyClipper/polyPlot
- **Explicit typing**: Type annotations for function parameters and returns

## Database & Infrastructure
- **Neo4j**: Remote SSH connection to EC2 instance with key pair authentication
- **PostgreSQL**: Direct LibPQ connection with spatial data support
- **AWS**: EC2 templates, S3 storage, credential management via `secrets.env`
- **Docker**: Full containerization support

## Development Guidelines

### **Mandatory for All New Code:**
1. **Follow module hierarchy exactly** - use correct module.function() syntax
2. **Use polyShape for core operations** (area, union, intersection, basic geometry)
3. **Use polyGdal for format conversion** (WKT, GDAL, buffering, hulls)
4. **Use polyClipper for offsetting** (polyOffset, Boolean operations)
5. **Use polyPlot for visualization** (all plotting functions)
6. **Use existing data structures** (PolyShape, LineShape, PointShape)
7. **Follow no-comments policy** - descriptive naming instead
8. **Use DotEnv for configuration** and SSH keys for database access

### **Never Do:**
- Mix up module functions (wrong module calls)
- Create new geometric data structures
- Add inline comments
- Use direct library calls (ArchGDAL, Clipper)
- Break Docker compatibility

## Current Status
- **Branch**: `dev_docker`
- **Recent updates**: Module separation, function reference corrections, Docker integration
- **Testing**: Custom validation - check project for specific test patterns
- **Build**: Verify with lint/typecheck commands if available

This modular architecture ensures maintainable, high-performance code for Chilean real estate development optimization.