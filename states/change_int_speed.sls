change speed and rollback:  
    junos.install_config:    
        - name: salt://speed.set    
        - comment: "configured using SaltStack"    
        - replace: False     
        - overwrite: False    
        - confirm: 2

