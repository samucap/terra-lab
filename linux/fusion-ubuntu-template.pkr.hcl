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

source "vmware-vmx" "ubuntu" {
  source_path      = "/Users/0x/Downloads/ubuntu-26.04-live-server-arm64.iso"
  vm_name          = "ubuntu-26.04-hardened-template"
  output_directory = "output_dir"

  vmx_data = {
    "firmware"                = "bios"
    "bios.bootOrder"          = "cdrom,disk"
    "uefi.secureBoot.enabled" = "false"
  }
  cd_files = ["./meta-data.yml", "./user-data.yml"]
  cd_label = "cidata"

  ssh_username     = "samworker"
  ssh_password     = "$6$rounds=4096$temp$hashedpasswordhere"
  shutdown_command = "shutdown -P now"

  skip_compaction = true
  boot_wait       = "30s"
  boot_command = [
    "c", "<wait3s>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud;", "<enter><wait3s>",
    "initrd /casper/initrd", "<enter><wait3s>",
    "boot", "<enter>"
  ]
}

build {
  sources = ["source.vmware-vmx.ubuntu"]
  provisioner "shell" {
    inline = [
      "apt-get update && apt-get upgrade -y && apt-get autoremove -y",
      "apt-get install -y ufw fail2ban lynis unattended-upgrades apparmor",
      "adduser --disabled-password --gecos '' samworker",
      "usermod -aG sudo samworker",
      "echo 'samworker ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/samworker",
      "sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "ufw --force enable",
      "ufw allow from 192.168.1.0/24 to any port 22",
      "systemctl enable --now fail2ban ssh",
      "lynis audit system --quiet --logfile /var/log/lynis-build.log"
    ]
  }
}
