using DotEnv 

display("HHHHHHHHHHHHHHHHHHH")
DotEnv.load("/app/src/secrets.env")

display(ENV["USER_AWS"])
display(ENV["PW_AWS"])
display(ENV["HOST_AWS"])
