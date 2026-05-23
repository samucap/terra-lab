packer {
  required_plugins {
    vmware = {
      version = ">= 1.0"
      source  = "github.com/hashicorp/vmware"
    }
    ansible = {
      version = ">= 1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "vmware-iso" "ubuntu" {
  network_adapter_type = "vmxnet3"
  iso_url              = "../../../Downloads/ubuntu-26.04-live-server-arm64.iso"
  iso_checksum         = "sha256:c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd"
  vm_name              = "ubuntu-26.04-hardened-template"
  cpus                 = 4
  memory               = 8192
  disk_size            = 20480
  ssh_username         = "samworker"
  ssh_password         = "HelloMoto1239"
  shutdown_command     = "shutdown -P now"

  headless         = true
  skip_compaction  = true
  output_directory = "output_dir"
  boot_command     = ["<esc><wait>linux /casper/vmlinuz quiet autoinstall <enter>"]
  boot_wait        = "20s"
}

build {
  sources = ["source.vmware-iso.ubuntu"]

  provisioner "shell" {
    inline = ["apt-get update && apt-get install -y ansible"]
  }

  provisioner "ansible" {
    playbook_file = "full-hardening.yml"
  }
}
