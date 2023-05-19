# Use the official Julia Docker image as the base
FROM julia:latest


# Copy the rest of your code into the container
COPY secrets.env /
COPY /src/script*.* /src/


# Install the Julia packages
RUN julia -e 'using Pkg; Pkg.instantiate(); Pkg.add("DotEnv"); \
             Pkg.add(url="https://github.com/PainterQubits/Devices.jl.git"); \
             Pkg.add(url="https://github.com/rjvial/LandValue.git")'



# Set the entry point for the container
CMD ["julia", "/src/script_2A_ejecutaCombinaciones_volumetrica.jl"]


# Use the official Julia Docker image as the base
#cd C:\Users\rjvia\Documents\Land_engines_code\Julia\LandValue
#docker build -t myimagename .
#docker run myimagename

