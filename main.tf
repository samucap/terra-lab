# 1. The 'null_resource' block.
# In a cloud module, this would be 'aws_instance'.
# Here, we use a placeholder resource to attach our connection logic.
resource "null_resource" "vm_provisioner" {

  # Connection Block: Tells Terraform how to communicate with the host.
  # This replaces the Cloud API authentication.
  connection {
    type        = "ssh"
    user        = var.ssh_user
    host        = var.vm_ip
    timeout     = "2m"
    agent = true
  }

  provisioner "file" {
    source = "${path.module}/scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }
  # Provisioner: remote-exec
  # This runs commands ON THE VM. It simulates 'User Data' in AWS.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "echo '${var.maru}' | sudo -S /tmp/setup.sh"
    ]
  }

  # Triggers: Ensure this runs if we change specific variables.
  triggers = {
    target_ip = var.vm_ip
    # Uncomment the line below to force it to run every single time
    # always_run = "${timestamp()}"
  }
}

# 2. Local File Resource
# Creates an 'inventory' file on your Mac, useful for later automation.
resource "local_file" "ansible_inventory" {
  content  = "[webservers]\n${var.vm_ip} ansible_user=${var.ssh_user}"
  filename = "${path.module}/inventory.ini"
}
