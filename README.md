# Documentation structure

[About the demo](#about-the-demo)  
[Requirements to run the demo](#requirements-to-run-the-demo)  
[Appformix](#appformix-1)  
[Docker](#docker)  
[Gitlab](#gitlab-1)  
[SaltStack](#saltstack-1)  
[Run the demo](#run-the-demo)  

# About the demo 

## Demo overview 

Appformix is used for network devices monitoring.  
Appformix send webhook notifications to SaltStack.   
The webhook notifications provides the device name and other details.  
SaltStack automatically configure the "faulty" JUNOS device.  

![Appformix-SaltStack-Junos.png](Appformix-SaltStack-Junos.png)  


## webhooks Overview 

- A webhook is notification using an HTTP POST. A webhook is sent by a system A to push data (json body as example) to a system B when an event occurred in the system A. Then the system B will decide what to do with these details. 
- Appformix supports webhooks. A notification is generated when the condition of an alarm is observed. You can configure an alarm to post notifications to an external HTTP endpoint. AppFormix will post a JSON payload to the endpoint for each notification.
- SaltStack can listens to webhooks and generate equivalents ZMQ messages to the event bus  
- SaltStack can reacts to webhooks


## Demo building blocks
- Junos devices
- Appformix
- Ubuntu with: 
    - SaltStack
    - Docker
    - Gitlab



## Building blocks role 

### Appformix
- Collects data from Junos devices (JTI native telemetry and SNMP)  
- Generates webhooks notifications (HTTP POST with a JSON body) to SaltStack when the condition of an alarm is observed. The JSON body provides the device name and other details


### Junos devices 
- Several Junos devices. 
- They are monitored by Appformix
- They are configured by SaltStack based on Appformix webhook notifications. 

### Ubuntu
- with Docker and SaltStack installed.  
- A Gitlab docker container is instanciated.  

### Gitlab  
- This SaltStack setup uses a gitlab server for external pillars (variables)
- This SaltStack setup uses a gitlab server as a remote files server 

### SaltStack
- One master, one minion, proxies (one proxy process per Junos device), webhook engine.  
- All in one setup with all above SaltStack components in the same Ubuntu host
- The Salt master listens to webhooks 
- The Salt master generates a ZMQ messages to the event bus when a webhook notification is received. The ZMQ message has a tag and data. The data structure is a dictionary, which contains information about the event.
- The Salt reactor binds sls files to event tags. The reactor has a list of event tags to be matched, and each event tag has a list of reactor SLS files to be run. So these sls files define the SaltStack reactions.
- The sls reactor file used in this content does the following: it parses the data from the ZMQ message to extract the network device name. It then ask to the proxy that manages the "faulty" Junos device to execute an sls file.
- The sls file executed by the Junos proxy minion will change the "faulty" device configuration 


# Requirements to run the demo 
- Install appformix
- Configure appformix for network devices monitoring
- Install Docker 
- Instanciate a Gitlab docker container
- Configure Gitlab
- Install SaltStack
- Configure SaltStack

# Appformix  

## Install Appformix. 
This is not covered by this documentation.  

## Configure Appformix for network devices monitoring 

Appformix supports network devices monitoring using SNMP and JTI (Juniper Telemetry Interface) native streaming telemetry.  
- For SNMP, the polling interval is 60s.  
- For JTI streaming telemetry, Appformix automatically configures the network devices. The interval configured on network devices is 60s.  

Here's the [**documentation**](https://www.juniper.net/documentation/en_US/appformix/topics/concept/appformix-ansible-configure-network-device.html)  

In order to configure AppFormix for network devices monitoring, here are the steps:
- manage the 'network devices json configuration' file. This file is used to define the list of devices you want to monitor using Appformix, and the details you want to collect from them.    
- Indicate to the 'Appformix installation Ansible playbook' which 'network devices json configuration file' to use. This is done by setting the variable ```network_device_file_name``` in ```group_vars/all```
- Set the flag to enable appformix network device monitor. This is done by setting the variable ```appformix_network_device_monitoring_enabled``` to ```true``` in ```group_vars/all```
- Enable the Appformix plugins for network devices monitoring. This is done by setting the variable ```appformix_plugins``` in ```group_vars/all```
- re run the 'Appformix installation Ansible playbook'.

Here's how to manage the 'network devices json configuration file' with automation:  
Define the list of devices you want to monitor using Appformix, and the details you want to collect from them:    
```
vi configure_appformix/network_devices.yml
```

Execute the python script [**network_devices.py**](configure_appformix/network_devices.py). It renders the template [**network_devices.j2**](configure_appformix/network_devices.j2) using the variables [**network_devices.yml**](configure_appformix/network_devices.yml). The rendered file is [**network_devices.json**](configure_appformix/network_devices.json).  
```
python configure_appformix/network_devices.py
```
```
more configure_appformix/network_devices.json
```

From your appformix directory, update ```group_vars/all``` file: 
```
cd appformix-2.15.2/
vi group_vars/all
```
to make sure it contains this:
```
network_device_file_name: /path_to/network_devices.json
appformix_network_device_monitoring_enabled: true
appformix_jti_network_device_monitoring_enabled: true
appformix_plugins:
   - plugin_info: 'certified_plugins/jti_network_device_usage.json'
   - plugin_info: 'certified_plugins/snmp_network_device_routing_engine.json'
   - plugin_info: 'certified_plugins/snmp_network_device_usage.json'
```

Then, from your appformix directory, re-run the 'Appformix installation Ansible playbook':
```
cd appformix-2.15.2/
ansible-playbook -i inventory appformix_standalone.yml
```
## Configure the network devices with the SNMP community used by Appformix

You need to configure the network devices with the SNMP community used by Appformix. The script [**snmp.py**](configure_junos/snmp.py) renders the template [**snmp.j2**](configure_junos/snmp.j2) using the variables [**network_devices.yml**](configure_appformix/network_devices.yml). The rendered file is [**snmp.conf**](configure_junos/snmp.conf). This file is then loaded and committed on all network devices used with SNMP monitoring.
 
Requirement: This script uses the junos-eznc python library so you need first to install it.  

```
python configure_junos/snmp.py
configured device 172.30.52.85 with snmp community public
configured device 172.30.52.86 with snmp community public
```
```
more configure_junos/snmp.conf
```

## Configure the network devices for JTI telemetry

For JTI native streaming telemetry, Appformix uses NETCONF to automatically configure the network devices:  
```
lab@vmx-1-vcp> show system commit
0   2018-03-22 16:32:37 UTC by lab via netconf
1   2018-03-22 16:32:33 UTC by lab via netconf
```
```
lab@vmx-1-vcp> show configuration | compare rollback 1
[edit services analytics]
+    sensor Interface_Sensor {
+        server-name appformix-telemetry;
+        export-name appformix;
+        resource /junos/system/linecard/interface/;
+    }
```
```
lab@vmx-1-vcp> show configuration | compare rollback 2
[edit]
+  services {
+      analytics {
+          streaming-server appformix-telemetry {
+              remote-address 172.30.52.157;
+              remote-port 42596;
+          }
+          export-profile appformix {
+              local-address 192.168.1.1;
+              local-port 21112;
+              dscp 20;
+              reporting-rate 60;
+              format gpb;
+              transport udp;
+          }
+          sensor Interface_Sensor {
+              server-name appformix-telemetry;
+              export-name appformix;
+              resource /junos/system/linecard/interface/;
+          }
+      }
+  }

lab@vmx-1-vcp>
```
Run this command to show the installed sensors: 
```
lab@vmx-1-vcp> show agent sensors
```

If Appformix has serveral ip addresses, and you want to configure the network devices to use a different IP address than the one configured by appformix for telemetry server, execute the python script [**telemetry.py**](configure_junos/telemetry.py). 
The python script [**telemetry.py**](configure_junos/telemetry.py) renders the template [**telemetry.j2**](configure_junos/telemetry.j2) using the variables [**network_devices.yml**](configure_appformix/network_devices.yml). The rendered file is [**telemetry.conf**](configure_junos/telemetry.conf). This file is then loaded and committed on all network devices used with JTI telemetry.  

```
more configure_appformix/network_devices.yml
```
Requirement: This script uses the junos-eznc python library so you need first to install it.  

```
python configure_junos/telemetry.py
configured device 172.30.52.155 with telemetry server ip 192.168.1.100
configured device 172.30.52.156 with telemetry server ip 192.168.1.100
```
```
# more configure_junos/telemetry.conf
set services analytics streaming-server appformix-telemetry remote-address 192.168.1.100
```
Verify on your network devices: 
```
lab@vmx-1-vcp> show configuration services analytics streaming-server appformix-telemetry remote-address
remote-address 192.168.1.100;

lab@vmx-1-vcp> show configuration | compare rollback 1
[edit services analytics streaming-server appformix-telemetry]
-    remote-address 172.30.52.157;
+    remote-address 192.168.1.100;

lab@vmx-1-vcp> show system commit
0   2018-03-23 00:34:47 UTC by lab via netconf

```
```
lab@vmx-1-vcp> show agent sensors

Sensor Information :

    Name                                    : Interface_Sensor
    Resource                                : /junos/system/linecard/interface/
    Version                                 : 1.1
    Sensor-id                               : 150000323
    Subscription-ID                         : 562950103421635
    Parent-Sensor-Name                      : Not applicable
    Component(s)                            : PFE

    Server Information :

        Name                                : appformix-telemetry
        Scope-id                            : 0
        Remote-Address                      : 192.168.1.100
        Remote-port                         : 42596
        Transport-protocol                  : UDP

    Profile Information :

        Name                                : appformix
        Reporting-interval                  : 60
        Payload-size                        : 5000
        Address                             : 192.168.1.1
        Port                                : 21112
        Timestamp                           : 1
        Format                              : GPB
        DSCP                                : 20
        Forwarding-class                    : 255

```

# Docker 


Check if Docker is already installed
```
$ docker --version
```

If it was not already installed, install it:
```
$ sudo apt-get update
```
```
$ sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common
```
```
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
```
```
$ sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
```
```
$ sudo apt-get update
```
```
$ sudo apt-get install docker-ce
```
```
$ sudo docker run hello-world
```
```
$ sudo groupadd docker
```
```
$ sudo usermod -aG docker $USER
```

Exit the ssh session and open an new ssh session and run these commands to verify you installed Docker properly:  
```
$ docker run hello-world

Hello from Docker!
This message shows that your installation appears to be working correctly.

To generate this message, Docker took the following steps:
 1. The Docker client contacted the Docker daemon.
 2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
    (amd64)
 3. The Docker daemon created a new container from that image which runs the
    executable that produces the output you are currently reading.
 4. The Docker daemon streamed that output to the Docker client, which sent it
    to your terminal.

To try something more ambitious, you can run an Ubuntu container with:
 $ docker run -it ubuntu bash

Share images, automate workflows, and more with a free Docker ID:
 https://hub.docker.com/

For more examples and ideas, visit:
 https://docs.docker.com/engine/userguide/
```
```
$ docker --version
Docker version 18.03.1-ce, build 9ee9f40
```

# Gitlab

This SaltStack setup uses a gitlab server for external pillars and as a remote file server.  

## Instanciate a Gitlab docker container


There is a Gitlab docker image available https://hub.docker.com/r/gitlab/gitlab-ce/


Pull the image: 
```
# docker pull gitlab/gitlab-ce
```

Verify: 
```
# docker images
REPOSITORY                   TAG                 IMAGE ID            CREATED             SIZE
gitlab/gitlab-ce             latest              09b815498cc6        6 months ago        1.33GB
```

Instanciate a container: 
```
docker run -d --rm --name gitlab -p 3022:22 -p 9080:80 gitlab/gitlab-ce
```
Verify:
```
# docker ps
CONTAINER ID        IMAGE                        COMMAND                  CREATED             STATUS                PORTS                                                 NAMES
9e8330425d9c        gitlab/gitlab-ce             "/assets/wrapper"        5 months ago        Up 5 days (healthy)   443/tcp, 0.0.0.0:3022->22/tcp, 0.0.0.0:9080->80/tcp   gitlab
```

Wait for Gitlab container status to be ```healthy```. It takes about 2 mns.   
```
$ watch -n 10 'docker ps'
```

Verify you can access to Gitlab GUI:  
Access Gitlab GUI with a browser on port 9080.  
http://gitlab_ip_address:9080  
Gitlab user is ```root```    
Create a password ```password```  
Sign in with ```root``` and ```password```    

## Configure Gitlab

### Create repositories

Create the group ```organization```.    

Create in the group ```organization``` the repositories:
   - ```network_parameters``` (Public, add Readme)
   - ```network_model``` (Public, add Readme) 

the repository ```network_parameters``` is used for SaltStack external pillars  
the repository ```network_model``` is used as an external files server for SaltStack  

### Add your public key to Gitlab

The Ubuntu host will inteact with the Gitlab server. 

#### Generate ssh keys
```
$ sudo -s
```
```
# ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''
```
```
# ls /root/.ssh/
id_rsa  id_rsa.pub  
```
#### Add the public key to Gitlab  
Copy the public key:
```
# more /root/.ssh/id_rsa.pub
```
Access Gitlab GUI, and add the public key to ```User Settings``` > ```SSH Keys```

### Update your ssh configuration
```
$ sudo -s
```
```
# touch /root/.ssh/config
```
```
# ls /root/.ssh/
config       id_rsa       id_rsa.pub  
```
```
# vi /root/.ssh/config
```
```
# more /root/.ssh/config
Host gitlab_ip_address
Port 3022
Host *
Port 22
```

### Configure your Git client

```
$ sudo -s
# git config --global user.email "you@example.com"
# git config --global user.name "Your Name"
```

### Verify you can use Git and Gitlab

Clone all the repositories:
```
$ sudo -s
# git clone git@gitlab_ip_address:organization/network_parameters.git
# git clone git@gitlab_ip_address:organization/network_model.git
# ls
# cd network_parameters
# git remote -v
# git branch 
# ls
# vi README.md
# git status
# git diff README.md
# git add README.md
# git status
# git commit -m 'first commit'
# git log --oneline
# git log
# git push origin master
# cd
```

# SaltStack 

## Install SaltStack 

- Install master
- Install minion 
- Install requirements for SaltStack Junos proxy

### Install master

Check if SaltStack master is already installed
```
$ sudo -s
```
```
# salt --version
```
```
# salt-master --version
```
if SaltStack master was not already installed, then install it: 
```
$ sudo -s
```
```
# wget -O - https://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2/SALTSTACK-GPG-KEY.pub | sudo apt-key add -
```
Add ```deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2 xenial main``` in the file ```/etc/apt/sources.list.d/saltstack.list```
```
# touch /etc/apt/sources.list.d/saltstack.list
```
```
# nano /etc/apt/sources.list.d/saltstack.list
```
```
# more /etc/apt/sources.list.d/saltstack.list
deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2 xenial main
```
```
# sudo apt-get update
```
```
# sudo apt-get install salt-master
```
Verify you installed properly SaltStack master 
```
# salt --version
salt 2018.3.2 (Oxygen)
```
```
# salt-master --version
salt-master 2018.3.2 (Oxygen)
```

### Install Minion

Check if SaltStack minion is already installed
```
# salt-minion --version
```
if SaltStack minion was not already installed, then install it: 
```
$ sudo -s
```
```
# wget -O - https://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2/SALTSTACK-GPG-KEY.pub | sudo apt-key add -
```
Add ```deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2 xenial main``` in the file ```/etc/apt/sources.list.d/saltstack.list```
```
# touch /etc/apt/sources.list.d/saltstack.list
```
```
# nano /etc/apt/sources.list.d/saltstack.list
```
```
# more /etc/apt/sources.list.d/saltstack.list
deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/archive/2018.3.2 xenial main
```
```
# sudo apt-get update
```
```
$ sudo apt-get install salt-minion
```
And verify if salt-minion was installed properly installation 
```
# salt-minion --version
salt-minion 2018.3.2 (Oxygen)
```

### Install requirements for SaltStack Junos proxy 

The Salt Junos proxy has some requirements (```junos-eznc``` python library and other dependencies). 

```
# apt-get install python-pip
# pip list
# apt-get --auto-remove --yes remove python-openssl
# pip install pyOpenSSL junos-eznc jxmlease jsnapy
# pip list | grep "pyOpenSSL\|junos-eznc\|jxmlease\|jsnapy"
```

## Configure SaltStack

- Configure SaltStack master
- Configure SaltStack minion 
- Configure SaltStack pillars
- Configure SaltStack proxy 
- Configure SaltStack files server
- Configure SaltStack webhook engine
- Configure SaltStack reactor

### Configure SaltStack master

#### SaltStack master configuration file

ssh to the Salt master and copy this [SaltStack master configuration file](master) in the file ```/etc/salt/master```  

```
cp automated_junos_configuration_changes_with_appformix_saltstack/master /etc/salt/master
more /etc/salt/master
```
So:
- the Salt master is listening webhooks on port 5001. It generates equivalents ZMQ messages to the event bus
- external pillars are in the gitlab repository ```organization/network_parameters```  (master branch)
- Salt uses the gitlab repository ```organization/network_model``` as a remote files server.  

#### Restart the salt-master service

```
# service salt-master restart
```
#### Verify the salt-master status

To see the Salt processes: 
```
# ps -ef | grep salt
```
To check the status, you can run these commands: 
```
# systemctl status salt-master.service
```
```
# service salt-master status
```
#### SaltStack master log

```
# more /var/log/salt/master 
```
```
# tail -f /var/log/salt/master
```

### Configure SaltStack minion 


#### SaltStack minion configuration file

Copy the [minion configuration file](minion) in the file ```/etc/salt/minion```

```
cp automated_junos_configuration_changes_with_appformix_saltstack/minion /etc/salt/minion
more /etc/salt/minion
```

#### Restart the salt-minion service


```
# service salt-minion restart
```

#### Verify the salt-minion status

To see the Salt processes: 
```
# ps -ef | grep salt
```
To check the status: 
```
# systemctl status salt-minion.service
```
```
# service salt-minion status
```

#### Verify the keys 

You need to accept the minions/proxies public keys on the master.   


To list all public keys:
```
# salt-key -L
```
To accept a specified public key:
```
# salt-key -a saltstack_minion_id -y
```
Or, to accept all pending keys:
```
# salt-key -A -y
```

#### Verify master <-> minion communication 

Run this command to make sure the minion is up and responding to the master. This is not an ICMP ping. 
```
# salt saltstack_minion_id test.ping
```
Run this additionnal test  
```
# salt "saltstack_minion_id" cmd.run "pwd"
```


### Configure SaltStack pillars

Pillars are variables     
They are defined in sls files, with a yaml data structure.  
There is a ```top``` file.  
The ```top.sls``` file map minions to sls (pillars) files.  

#### Pillar configuration

Refer to the [master configuration file](master) to know the location for pillars. 
```
more /etc/salt/master
``` 
So it is the repository ```network_parameters```  
Run these commands to add the [pillars](pillars) at the root of the repository ```network_parameters```: 

```
# cp automated_junos_configuration_changes_with_appformix_saltstack/pillars/* network_parameters/
# ls network_parameters/
# cd network_parameters
# git status
# git add .
# git status
# git commit -m "add pillars"
# git push origin master
# cd
```


#### Pillars configuration verification

```
$ sudo -s
```
```
# salt-run pillar.show_pillar
```
```
# salt-run pillar.show_pillar dc-vmx-1
```

### Configure SaltStack proxy 

#### SaltStack proxy configuration file

Copy the [proxy configuration file](proxy) in the file ```/etc/salt/proxy```  

```
# cp automated_junos_configuration_changes_with_appformix_saltstack/proxy /etc/salt/proxy
# more /etc/salt/proxy
```


#### Start SaltStack proxy 

You need one salt proxy process per Junos device.  

to start the proxy as a daemon for the device ```dc-vmx-1```, run this command
```
# sudo salt-proxy -d --proxyid=dc-vmx-1
```
The proxy daemon ```dc-vmx-1``` manages the network device ```dc-vmx-1```.  

you can run this command to start it with a debug log level: 
```
# sudo salt-proxy -l debug --proxyid=dc-vmx-1
```

To see the SaltStack processes, run this command: 
```
# ps -ef | grep salt
```

#### Verify the keys

You need to accept the minions/proxies public keys on the master.   


To list all public keys:
```
# salt-key -L
```
To accept a specified public key:
```
# salt-key -a dc-vmx-1 -y
```
Or, to accept all pending keys:
```
# salt-key -A -y
```
#### Verify master <-> proxy communication

Run this command to make sure a proxy is up and responding to the master. This is not an ICMP ping. 
```
# salt 'dc-vmx-1' test.ping
```
Run this additionnal test. It is an execution module. The master asks to the proxy ```dc-vmx-1``` to use an execution module
```
# salt 'dc-vmx-1' junos.cli "show version"
```


### Configure SaltStack files server

Salt runs a files server to deliver files to minions and proxies.  
The [master configuration file](master) indicates the location for the files server.  
We are using an external files server (gitlab repository ```organization/network_model```)


#### templates for Junos

Run these commands to copy these [Junos templates](templates) at the root of the repository ```network_model```.

```
# cp automated_junos_configuration_changes_with_appformix_saltstack/templates/* network_model/
# cd network_model/
# git add .
# git commit -m "add junos templates"
# git push origin master
# cd
```


 
#### SaltStack state files

Salt establishes a client-server model to bring infrastructure components in line with a given policy (salt state modules, in salt state sls files. kind of Ansible playbooks).

run these commands to copy [these states files](states) at the root of the repository ```network_model```

```
# cp automated_junos_configuration_changes_with_appformix_saltstack/states/* network_model/
# cd network_model/
# git add *
# git commit -m "add states files"
# git push origin master
# cd
```




### Test your automation content manually from the master

Example with the proxy ```dc-vmx-1``` (it manages the network device ```dc-vmx-1```).   
Run this command on the master to ask to the proxy ```dc-vmx-1``` to execute the state file [isis.sls](states/isis.sls).  
```
salt dc-vmx-1 state.apply isis
```

Verify on the junos device itself.  
ssh to the network device ```dc-vmx-1``` and run these commands: 
```
show configuration | compare rollback 1
show configuration protocols isis
show system commit
```

### Configure SaltStack webhook engine

Engines are executed in a separate process that is monitored by Salt. If a Salt engine stops, it is restarted automatically.  
Engines can run on both master and minion.  To start an engine, you need to specify engine information in master/minion config file depending on where you want to run the engine. Once the engine configuration is added, start the master and minion normally. The engine should start along with the salt master/minion.   
webhook engine listens to webhook, and generates and pusblishes messages on SaltStack 0MQ bus.  

We already added the webhook engine configuration in the [master configuration file](master)  
So Appformix should his webhook notifications to the master ip address on port 5001. 

```
# more /etc/salt/master
```

### Configure SaltStack reactor

#### Configure reactor configuration file

The reactor binds sls files to event tags. The reactor has a list of event tags to be matched, and each event tag has a list of reactor SLS files to be run. So these sls files define the SaltStack reactions.  

To map some events to reactor sls files, copy the [reactor configuration file](reactor.conf) to ```/etc/salt/master.d/reactor.conf```  

```
# cp automated_junos_configuration_changes_with_appformix_saltstack/reactor.conf /etc/salt/master.d/
# more /etc/salt/master.d/reactor.conf
```
This reactor binds webhook from Appformix to to ```/srv/reactor/enforce_isis.sls``` 

#### Restart the salt master service
```
# service salt-master restart
```
#### Verify the reactor operationnal state: 
```
# salt-run reactor.list
```
#### Add your reactor sls files
create a ```/srv/reactor/``` directory    
```
# mkdir /srv/reactor/
```
and copy these sls reactor files [reactor](reactor) to the directory ```/srv/reactor/```
```
# cp automated_junos_configuration_changes_with_appformix_saltstack/reactor/* /srv/reactor/
# ls /srv/reactor/
# more /srv/reactor/enforce_isis.sls
```
The reactor file [enforce_isis.sls](reactor/enforce_isis.sls) parses the data from the ZMQ message that has the tags ```salt/engines/hook/appformix_to_saltstack``` and extracts the network device name.  
It then asks to the Junos proxy minion that manages the "faulty" device to apply the state file [isis.sls](states/isis.sls).  
the state file [isis.sls](states/isis.sls) executed by a Junos proxy will change the device configuration using the template [isis.set](templates/isis.set) and a variable defined in [production.sls](pillars/production.sls) 

# Run the demo: 

## Create Appformix webhook notifications.  

You can do it from Appformix GUI, settings, Notification Settings, Notification Services, add service.    
Then:  
service name: appformix_to_saltstack  
URL endpoint: provide the Salt master IP and Salt webhook listerner port (```HTTP://192.168.128.174:5001/appformix_to_saltstack``` as example).  
setup  

## Create Appformix alarms, and map these alarms to the webhook you just created.

You can do it from the Appformix GUI, Alarms, add rule.  
Then, as example:   
Name: in_unicast_packets_dc-vmx-1,  
Module: Alarms,  
Alarm rule type: Static,  
scope: network devices,  
network device/Aggregate: dc-vmx-1,  
generate: generate alert,  
For metric: interface_in_unicast_packets,  
When: Average,  
Interval(seconds): 60,  
Is: Above,  
Threshold(Packets/s): 300,  
Severity: Warning,  
notification: custom service,  
services: appformix_to_saltstack,  
save.

## Verify the salt master receives webhook motifications from Appformix

Run this command on the master to see webhook notifications:
```
# tcpdump port 5001 -XX 
```

## ZMQ messages  


Salt provides a runner that displays events in real-time as they are received on the Salt master:  
```
# salt-run state.event pretty=True
```

## Trigger an alarm  to get a webhook notification sent by Appformix to SaltStack 

Either you DIY, or, depending on the alarms you set, you can use one the automation content available in the repository.  
Here's how to use the automation content available in the repository to trigger an alarm.   

### generate traffic between 2 routers 

[generate_traffic.sls](states/generate_traffic.sls)  

```
# more network_model/generate_traffic.sls
# salt "dc-vmx-1" state.apply generate_traffic
```
### Change interface speed on a router

[change_int_speed.sls](states/change_int_speed.sls)  
[speed.set](templates/speed.set)  

```
# more network_model/change_int_speed.sls
# more network_model/speed.set   
# salt "dc-vmx-1" state.apply change_int_speed
# salt "dc-vmx-1" junos.cli "show system commit"
# salt "dc-vmx-1" junos.cli "show configuration | compare rollback 1"
# salt "dc-vmx-1" junos.cli "show configuration interfaces ge-0/0/1"
```

### Change MTU on a router

[change_mtu.sls](states/change_mtu.sls)  
[mtu.set](templates/mtu.set)  

```
# more network_model/change_mtu.sls
# more network_model/mtu.set  
# salt "dc-vmx-1" state.apply change_mtu
# salt "dc-vmx-1" junos.cli "show system commit"
# salt "dc-vmx-1" junos.cli "show configuration | compare rollback 1"
# salt "dc-vmx-1" junos.cli "show configuration interfaces ge-0/0/1"
```

## Verify on the Junos device 

ssh to the junos device and run these commands: 
```
show configuration protocols isis
show system commit
```

