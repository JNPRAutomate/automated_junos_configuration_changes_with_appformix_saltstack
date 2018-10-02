change mtu and rollback:  
    junos.install_config:    
        - name: salt://mtu.set    
        - comment: "configured using SaltStack"    
        - replace: False     
        - overwrite: False    
        - confirm: 2

