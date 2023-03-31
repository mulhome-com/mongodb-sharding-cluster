## mongodb-sharding-cluster

Run the shell script by 

> bash build.sh -a 10.11.12.101,10.11.12.102,10.11.12.103 -m 10.11.12.104 -n rs0

There are four hosts in the environment. 

Build the config server in the following hosts with the port 27018:

- 10.11.12.101
- 10.11.12.102
- 10.11.12.103


Build the sharding replic set in the following hosts with the port 27019 :

- 10.11.12.101
- 10.11.12.102
- 10.11.12.103


And the 10.11.12.104 as the mongos server with port 27017 .
