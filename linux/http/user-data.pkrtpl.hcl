#cloud-config
autoinstall:
  version: 1

  locale: en_US.UTF-8
  keyboard:
    layout: us
  timezone: UTC

  # --- Storage: single ext4 root + swap file (no LVM complexity) ---
  storage:
    layout:
      name: direct

  # --- Initial user (matches Packer ssh_username) ---
  identity:
    hostname: ${hostname}
    username: ${username}
    password: "${password_hash}"

  # --- SSH: enabled temporarily for Packer build, disabled in final image ---
  ssh:
    install-server: true
    allow-pw: true

  # --- Packages installed during OS install ---
  packages:
    - open-vm-tools
    - open-vm-tools-desktop
    - python3
    - python3-apt
    - openssh-server
    - curl
    - ca-certificates

  # --- Post-install commands ---
  late-commands:
    # Enable passwordless sudo for initial user during Packer build
    - echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${username}
    - chmod 440 /target/etc/sudoers.d/${username}
    # SSH enabled here for Packer provisioners — disabled in cleanup stage
    - curtin in-target --target=/target -- systemctl enable ssh
