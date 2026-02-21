#!/bin/bash
apt-get update -y
apt-get install -y git htop build-essential vim docker.io
systemctl start docker
