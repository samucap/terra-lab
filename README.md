# configurable scripts for automation and management

## automating vm management with packer, vagrant, ansible

    * spinning up local vms for rapid reusability
        - to run: 'packer init .' > packer build .hcl file > vagrant up --provider=vmware_desktop

#### Dependencies

    - vagrant plugin install dotenv
