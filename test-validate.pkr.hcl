packer {
  required_plugins {
    vmware = {
      version = ">= 1.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}
source "vmware-iso" "test" {
  iso_url = "none"
  iso_checksum = "none"
  cd_label = "cidata"
  cd_content = {
    "meta-data" = "instance-id: test"
  }
  ssh_username = "user"
}
build {
  sources = ["source.vmware-iso.test"]
}
