# Demo overview:  
Appformix is used for network devices monitoring.  
Appformix send webhook notifications to SaltStack.   
The webhook notifications provides the device name and other details.  
SaltStack automatically configure the "faulty" JUNOS device.  

![Appformix-SaltStack-Junos.png](Appformix-SaltStack-Junos.png)  

# Demo building blocks: 

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

### Install Appformix. 
This is not covered by this documentation.  

### Configure Appformix for network devices monitoring 

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
### Configure the network devices with the SNMP community used by Appformix

You need to configure the network devices with the SNMP community used by Appformix. The script [**snmp.py**](configure_junos/snmp.py) renders the template [**snmp.j2**](configure_junos/snmp.j2) using the variables [**network_devices.yml**](configure_appformix/network_devices.yml). The rendered file is [**snmp.conf**](configure_junos/snmp.conf). This file is then loaded and committed on all network devices used with SNMP monitoring.
 
```
python configure_junos/snmp.py
configured device 172.30.52.85 with snmp community public
configured device 172.30.52.86 with snmp community public
```
```
more configure_junos/snmp.conf
```

### Configure the network devices for JTI telemetry

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


## SaltStack 

### Install SaltStack 

This is not covered by this documentation. 

You need a  master and a minion.  

The Salt Junos proxy has some requirements (```junos-eznc``` python library and other dependencies).  
Install on the master or on a minion the dependencies to use a SaltStack proxy for Junos.  

You need one junos proxy daemon per device.   
Start one junos proxy daemon per device.  

### Validate your SaltStack setup 

Run this command on the master to verify: 
```
salt-key -L
```

Run this command to make sure the minion is up and responding to the master. This is not an ICMP ping.
```
salt -G 'roles:minion' test.ping
```

Select one the junos proxy and run these additionnal tests.  
Example with the proxy ```core-rtr-p-02``` (it manages the network device ```core-rtr-p-02```)
```
salt core-rtr-p-02 test.ping
```
```
salt core-rtr-p-02 junos.cli "show version"
```
### Edit the SaltStack master configuration file 

Edit the salt master configuration file:  
```
vi /etc/salt/master
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
- external pillars (variables) are in the gitlab repository ```organization/network_parameters``` (master branch)
- Salt uses the gitlab repository ```organization/network_model``` as a remote file server.  

### Create the junos automation content

#### junos automation content in gitfs_remotes

Add the file [isis.sls](isis.sls) to the directory ```junos``` of the gitlab repository ```organization/network_model``` (```gitfs_remotes```). 
```
salt://templates/junos/isis.set:
  junos:
    - install_config
    - comment: "configured using SaltStack"
```
The file [isis.sls](isis.sls) uses the ```junos``` module ```install_config``` with the file ```templates/junos/isis.set```.   

Add the file [isis.set](isis.set) to the directory ```templates/junos``` of the gitlab repository ```organization/network_model``` (```gitfs_remotes```).  
```
set protocols isis {{ pillar["isis_details"] }}
```

#### junos automation content in ext_pillar

Here's an example for the ```top.sls``` file at the root of the gitlab repository ```organization/network_parameters``` (```ext_pillar```):  
```
{% set id = salt['grains.get']('id') %} 
{% set host = salt['grains.get']('host') %} 

base:
  '*':
    - production
   
{% if host == '' %}
  '{{ id }}':
    - {{ id }}
{% endif %}
```

Update the file ```production.sls``` in the repository ```organization/network_parameters``` (```ext_pillar```) to define the pillar ```isis_details```  
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

## Trigger an alarm  to get a webhook notification sent by Appformix to SaltStack 

Either you DIY, or, depending on the alarms you set, you can use one the automation content available in the directory [trigger_alarms](trigger_alarms):  

Add the file [generate_traffic.sls](trigger_alarms/generate_traffic.sls) to the directory ```junos``` of the repository ```organization/network_model``` (```gitfs_remotes```).  

And run this command on the master:   
```
# salt "core-rtr-p-02" state.apply junos.generate_traffic
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
