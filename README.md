# Overview:  
Appformix is used for network devices monitoring.  
Appformix send webhook notifications to SaltStack.   
The webhook notifications provides the device name and other details.  
SaltStack automatically configure the "faulty" JUNOS device. 

# Building blocks: 

- Juniper devices
- Appformix
- SaltStack

# webhooks Overview: 

- A webhook is notification using an HTTP POST. A webhook is sent by a system A to push data (json body as example) to a system B when an event occurred in the system A. Then the system B will decide what to do with these details. 
- Appformix supports webhooks. A notification is generated when the condition of an alarm is observed. You can configure an alarm to post notifications to an external HTTP endpoint. AppFormix will post a JSON payload to the endpoint for each notification.
- SaltStack can listens to webhooks and generate equivalents ZMQ messages to the event bus  
- SaltStack can reacts to webhooks

# Building blocks role: 

## Appformix:  
- Collects data from Junos devices.
- Generates webhooks notifications (HTTP POST with a JSON body) to SaltStack when the condition of an alarm is observed. The JSON body provides the device name and other details. 

## SaltStack: 
- In addition to the Salt master, Salt Junos proxy minions are required (one process per Junos device is required)  
- The Salt master listens to webhooks 
- The Salt master generates a ZMQ messages to the event bus when a webhook notification is received. The ZMQ message has a tag and data. The data structure is a dictionary, which contains information about the event.
- The Salt reactor binds sls files to event tags. The reactor has a list of event tags to be matched, and each event tag has a list of reactor SLS files to be run. So these sls files define the SaltStack reactions.
- The sls reactor file used in this content does the following: it parses the data from the ZMQ message to extract the network device name. It then ask to the Junos proxy minion that manages the "faulty" device to execute an sls file.
- The sls file executed by the Junos proxy minion will change the "faulty" device configuration 

## Junos devices: 
- They are monitored by Appformix
- They are configured by SaltStack based on Appformix notifications. 

# Requirements: 

- Install appformix
- Configure appformix for network devices monitoring
- Install SaltStack

# Prepare the demo: 

## Appformix  

Install Appformix. This is not covered by this documentation.  
Configure Appformix for network devices monitoring. This is not covered by this documentation

## SaltStack 

### Install the master and a minion.    
This is not covered by this documentation.  

### Install the Junos proxy role to a minion 

ssh to the Salt master.  

On the Salt master, list all the keys. Make sure the minion key is accepted.  
```
salt-key -L
```

Run this command to make sure the minion is up and responding to the master. This is not an ICMP ping.
```
salt -G 'roles:minion' test.ping
```

The Salt Junos proxy has some requirements (```junos-eznc``` python library and other dependencies).    

```
# more /srv/salt/jnpr/junos_proxy.sls
include:
  - jnpr.linux

install_pyez_deps:
  pkg.installed:
    - pkgs:
        - python-pip
        - python-lxml
        - python-dev
        - libssl-dev
        - libxslt-dev
        - python-paramiko

install_pyez:
  pip.installed:
    - name: junos-eznc
    - require:
      - install_pyez_deps

install_jxmlease:
  pip.installed:
    - name: jxmlease
    - require:
      - install_pyez

set_grain:
  grains.list_present:
    - name: roles
    - value: junos_proxy_minion

copy_proxy_config:
  file.managed:
    - name: /etc/salt/proxy
    - source: salt://templates/minion/proxy
    - template: jinja
    - defaults:
        master: {{ grains["master"] }}

# configure a systemd service to start and monitor the process as well
{% if pillar['proxy_device'] is defined %}

create_systemd_config:
  file.managed:
    - name: /etc/systemd/system/salt-proxy@.service
    - source: salt://templates/minion/salt-proxy.service

start_salt_proxy_process:
  service.running:
    - name: salt-proxy@{{ pillar['proxy_device'] }}
    - enable: True

set_proxy_child_grain:
  grains.list_present:
    - name: proxies
    - value: {{ pillar['proxy_device'] }}

{%  endif %}
```

Run this command on the master to install the Salt Junos proxy role on a minion. 
Example for the minion ```svl-util-01``` 
```
salt "svl-util-01" state.apply jnpr.junos_proxy
```

Grains are static information collected from the minions.  
Run this command on the master to return all grains from a minion. 
```
salt "svl-util-01" grains.items
```
You should see the grain ```roles:junos_proxy_minion```.      

Run this command to check if the minions that has the ```roles:junos_proxy_minion```role are up and responding to the master:   
```
salt -G 'roles:junos_proxy_minion' test.ping
```

### Create junos proxy daemons 

You need one junos proxy daemon per device.  

Run this command to open the salt master configuration file:  
```
more /etc/salt/master
```
It should include this content:   
```
jnpr_config:
  driver: yaml
  files:
    - /etc/salt/jnpr_config.yml
```
It means SaltStack configuration is kept in SDB module.  
The file ```/etc/salt/jnpr_config.yml``` has the SaltStack configuration.  
```
more /etc/salt/jnpr_config.yml
```
This file includes:  
```
auth:
  junos_username: root
  junos_password: Clouds123
``` 

If you want to change the junos username or password, edit the file ```/etc/salt/jnpr_config.yml``` on the master.  

You need one junos proxy daemon per device: Here's how to automate this using the Salt reactor.   

The reactor binds sls files to event tags.  
The reactor has a list of event tags to be matched, and each event tag has a list of reactor SLS files to be run.  
So these sls files define the SaltStack reactions.  
Update the reactor with this content:   
This reactor binds ```salt/engines/hook/gitlab``` to ```/srv/reactor/proxy_inventory.sls``` 
```
more /etc/salt/master.d/reactor.conf
reactor:
   - 'salt/engines/hook/gitlab':
     - /srv/reactor/proxy_inventory.sls
```

Then restart the Salt master:
```
service salt-master stop
service salt-master start
```

The command ```salt-run reactor.list``` lists currently configured reactors. Use it to verify the reactor actual configuration  
```
salt-run reactor.list
```

The event ```salt/engines/hook/gitlab``` is generated and sent to the event bus when a change is done in the gitlab repository ```nora_ops/network_model```.  
The reactor subscribes to the event 'salt/engines/hook/gitlab' and runs the sls reactor file ```/srv/reactor/proxy_inventory.sls```.   
The sls reactor file ```/srv/reactor/proxy_inventory.sls``` creates automatically the junos proxy daemons for each devices defined in the gitlab repository ```nora_ops/network_model```.    

Run this command to open the salt master configuration file: 
```
more /etc/salt/master
```
It includes this content: 
```
fileserver_backend:
  - git
  - roots
```
```
gitfs_remotes:
  - ssh://git@gitlab/organization/network_model.git
  
```
It means Salt use the gitlab repository ```organization/network_model``` as a remote file server.  
Create a directory ```inventory``` at the root of the repository ```organization/network_model``` (master branch).  
Create a file ```inventory.yml``` in the directory inventory
Update the  file ```inventory.yml``` with the name and ip address of your network devices. 
Example: 
```
---
network_devices:
  dc-vmx-1: 172.30.52.85
  dc-vmx-2: 172.30.52.86
  vmx-1-vcp: 172.30.52.155 
  vmx-2-vcp: 172.30.52.156
  core-rtr-p-02: 172.30.52.152
``` 

This automatically created a junos proxy daemon for each device in the ```inventory.yml``` file.  
These daemons are in minions that has the ```junos_proxy_minion``` role  
Each proxy has the same name as the device it controls.  

### Validate the junos proxies

Run this command on the master to verify: 
```
salt-key -L
```

Select one the proxy and run these additionnal tests.  
Example with the proxy ```core-rtr-p-02``` (it manages the network device ```core-rtr-p-02```)
```
salt core-rtr-p-02 test.ping
```
```
salt core-rtr-p-02 junos.cli "show version"
```

Run this command to open the salt master configuration file: 
```
more /etc/salt/master
```
It includes this content: 
```
ext_pillar:
  - git:
    - master git@gitlab:organization/network_parameters.git
```

Pillars are variables. External pillars are in the gitlab repository ```organization/network_parameters``` (master branch)

Verify the pillars automatically created for the proxies. 


### Create the junos automation content

ssh to the Salt master and open the salt master configuration file:  
```
more /etc/salt/master
```
Make sure the master configuration file has these details:  
```
runner_dirs:
  - /srv/runners
```
```
engines:
  - webhook:
      port: 5001
```
```
ext_pillar:
  - git:
    - master git@gitlab:organization/network_parameters.git
```
```
fileserver_backend:
  - git
  - roots
```
```
gitfs_remotes:
  - ssh://git@gitlab/organization/network_model.git
  
```

So: 
- the Salt master is listening webhooks on port 5001. It generates equivalents ZMQ messages to the event bus
- runners are in the directory ```/srv/runners``` on the Salt master
- external pillars (humans defined variables) are in the gitlab repository ```organization/network_parameters``` (master branch)
- Salt uses the gitlab repository ```organization/network_model``` as a remote file server.  

Add the file ```junos/isis.sls``` to the ```organization/network_model``` repository. 
```
salt://templates/junos/isis.set:
  junos:
    - install_config
    - comment: "configured using SaltStack"
```

The file ```junos/isis.sls``` uses the ```junos``` module ```install_config``` with the file ```templates/junos/isis.set``` 

Add the file ```templates/junos/isis.set```  to the ```organization/network_model``` repository.
```
set protocols isis {{ pillar["isis_details"] }}
```

Update the file ```production.sls``` in the repository ```organization/network_parameters``` to define the pillar ```isis_details```  
```
isis_details: overload

```

### Test your automation content manually

Test your automation content manually from the master. 
Example with the proxy ```core-rtr-p-02``` (it manages the network device ```core-rtr-p-02```) 

```
salt core-rtr-p-02 state.apply junos.isis
```

Verify on the junos device itself. ssh to the network device ```core-rtr-p-02``` and run these commands: 
```
show configuration | compare rollback 1
```
```
show configuration protocols isis
```
```
show system commit
```


###  Update the Salt reactor

Update the Salt reactor file  
The reactor binds sls files to event tags. The reactor has a list of event tags to be matched, and each event tag has a list of reactor SLS files to be run. So these sls files define the SaltStack reactions.  
Update the reactor.  
This reactor binds ```salt/engines/hook/appformix_to_saltstack``` to ```/srv/reactor/enforce_isis.sls``` 

```
# more /etc/salt/master.d/reactor.conf
reactor:
   - 'salt/engines/hook/appformix_to_saltstack':
       - /srv/reactor/enforce_isis.sls

```

Restart the Salt master:
```
service salt-master stop
service salt-master start
```

The command ```salt-run reactor.list``` lists currently configured reactors:  
```
salt-run reactor.list
```

Create the sls reactor file ```/srv/reactor/enforce_isis.sls```.  
It parses the data from the ZMQ message that has the tags ```salt/engines/hook/appformix_to_saltstack``` and extracts the network device name.  
It then ask to the Junos proxy minion that manages the "faulty" device to apply the ```junos/isis.sls``` file.  
the ```junos/isis.sls``` file executed by the Junos proxy minion will change the "faulty" device configuration.  

```
# more /srv/reactor/enforce_isis.sls
{% set body_json = data['body']|load_json %}
{% set devicename = body_json['status']['entityId'] %}

enforce_isis_overload:
  local.state.apply:
    - tgt: "{{ devicename }}"
    - arg:
      - junos.isis

```

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
Name: in_unicast_packets_core-rtr-p-02,  
Module: Alarms,  
Alarm rule type: Static,  
scope: network devices,  
network device/Aggregate: core-rtr-p-02,  
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

## Watch webhook notifications and ZMQ messages  

Run this command on the master to see webhook notifications:
```
# tcpdump port 5001 -XX 
```

Salt provides a runner that displays events in real-time as they are received on the Salt master:  
```
# salt-run state.event pretty=True
```

- Trigger an alarm  to get a webhook notification sent to SaltStack 
```
salt "core-rtr-p-02" junos.rpc 'ping' rapid=True
```

## Verify on the Junos device 

ssh to the junos device and run these commands: 
```
show configuration | compare rollback 1
```
```
show configuration protocols isis
```
```
show system commit
```



