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
