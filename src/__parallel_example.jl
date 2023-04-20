using Distributed
#addprocs(4; exeflags="--project")

addprocs(6)

#rmprocs(6,5) #Remove the worker 6 and 5

dir_str = @__DIR__
@everywhere begin
    using Pkg; Pkg.activate(dir_str)
    Pkg.instantiate(); Pkg.precompile()
  end

@everywhere using LandValue
println("Number of Cores: " * string(nprocs()))
println("Number of Workers: " * string(nworkers()))

for i in workers()
    id, pid, host = fetch(@spawnat i (myid(), getpid(), gethostname()))
    println(id, " ", pid, " Hello from ", host)
end


@everywhere x=3
f = @spawn (x.^2, myid())
fetch(f)

@everywhere function myfun(v)
  max_val = maximum(v)
  min_val = minimum(v)
  return max_val, min_val
end
f = remotecall(myfun, 3, [3,2,50,4])
fetch(f)

A = rand(10,10) #Variable Global definida en script proceso 1
remotecall_fetch(()->sum(A), 2) #Realiza la suma de los elementos de A y genera copia de A en 2
@fetchfrom 2 InteractiveUtils.varinfo()

let B = rand(10,10)
  remotecall_fetch(()->sum(B), 3) #Realiza la suma de los elementos de B, pero no genera copia de B en 3
end
@fetchfrom 3 InteractiveUtils.varinfo()

# @distributed for can handle situations where each iteration is tiny, perhaps merely summing two numbers
# Este código no funciona porque inicializa a en cada proceso, por lo que a no es compartida
a = zeros(10)
@distributed for i = 1:10
    a[i] = i
end

# Este código si funciona porque se comparte a en todos los procesos
using SharedArrays
a = SharedArray{Float64}(10)
@distributed for i = 1:10
    a[i] = i
end

# Una forma alternativa de paralelizar usando pmap
# Julia's pmap is designed for the case where each function call does a large amount of work.
M = Matrix{Float64}[rand(1000,1000) for i = 1:10]
pmap(sum, M)


# Ejemplo canales (Channels). No requiere Distributions
function fib(c::Channel) # Genera resultados secuenciales y los asigna a un canal (c)
  put!(c, "Soy una suculenta serie de Fibonacci entrando en el canal de Fibonacci")
  a = 0
  b = 1
  for n=1:6
      a, b = b, a+b
      put!(c, b)
  end
  put!(c, "Soy una suculenta serie de Fibonacci saliendo del canal de Fibonacci")
end

chnl = Channel(fib);
println(take!(chnl)) #Imprime el siguiente resultado previamente asignado al canal (chnl) 
println(take!(chnl))

chnl = Channel(fib) #Imprime todos los resultados previamente asignado al canal (chnl) 
for i in chnl
  println(i)
end


##########################################################
######### EJEMPLO PRINCIPAL ##############################
##########################################################

# @async Macro takes care of creating a function, wrapping it in a Task and the scheduling that task. 
# It will return the task object, but we don't need to store it for anything.
using Distributed
addprocs(4)

const jobs = RemoteChannel(()->Channel{Int}(32))
const results = RemoteChannel(()->Channel{Tuple}(32))

@everywhere function distributed_work(jobs, results) # Saca un job del channel y lo ejecuta, y después guarda el resultado en el channel results
  while true
      job_id = take!(jobs)
      exec_time = rand()
      sleep(exec_time) # simulates elapsed time doing actual work
      put!(results, (job_id, exec_time, myid()))
  end
end

function make_jobs(n) # Genera un numero n de jobs y los guarda en el channel jobs
  for i in 1:n
      put!(jobs, i)
  end
end

n = 12

@async make_jobs(n)

# Este codigo asigna los workers para que realicen el trabajo
for p in workers() # start tasks on the workers to process requests in parallel
  #Executes f on worker id asynchronously. Unlike remotecall, it does not store 
  # the result of computation, nor is there a way to wait for its completion.
  remote_do(distributed_work, p, jobs, results) # Los parametros jobs, results son pasados a distributed_work()
end

# Este codigo solo sirve para imprimir la información del channel results
@elapsed while n > 0 # print out results
  job_id, exec_time, wkr = take!(results)
  println("Job $job_id finished in $(round(exec_time; digits=2)) seconds by worker $wkr")
  global n = n - 1
end

