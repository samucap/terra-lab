## some network, some cybersec stuff

## in ./linux automating virtual machines setup

    * Vagrant, ansible, packer
    * automating spinning up local vms for rapid setup/teardown/rebuild for labs, sandboxes, malware analysis, etc.
        - hardened w/ security features and configurable via scripts (ansible, vagrant, packer, etc.)
    * to run: cd ./linux && vagrant up --provider=virtualbox

#### Dependencies

    - install hashicorp/tap/hashicorp-vagrant ansible
    - install --cask virtualbox
    - virtualbox/vmware fusion pro or any other hypervisor provider supported by vagrant
    - vagrant plugin install dotenv

#### TODO

    - do i need bios password? boot pw?
    - disable unused ports, services
    - verify installation and lynis initial audit
    - need to snapshot initial processes, so can keep record of truth
    - need to set user password
    - add the option for vagrant to clone something that speeds up build
