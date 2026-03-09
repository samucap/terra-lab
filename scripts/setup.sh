#!/bin/bash
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y git htop build-essential vim docker.io unzip libssl-dev pkg-config clang cmake libpcap-dev

# Download and install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Press '1' and Enter to proceed with default installation. new terminal session to see rust

# TODO: add a check to see if cargo

# terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt-get install terraform

# docker
sudo usermod -aG docker $USER
# log out and back

systemctl start docker
