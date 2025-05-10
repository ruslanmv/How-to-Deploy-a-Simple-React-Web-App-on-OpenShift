#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- CONFIGURATION ---
STABLE="v1.30"  # target Kubernetes minor version branch
# As of May 2025 (current date), please verify the latest stable minor version for pkgs.k8s.io
# by visiting https://kubernetes.io/releases/ or checking the available directories at
# https://pkgs.k8s.io/core:/stable:/
# For example, if v1.33 is the latest desired stable, update STABLE="v1.33".
# v1.30 should still be available but might not be the most recent.

echo
echo "👉 Installing kubectl (target: $STABLE)..."
echo

# 1) Prereqs
echo "Updating package lists and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg apt-transport-https

# 2) Clean old k8s repos
echo "Cleaning up old Kubernetes repository configurations..."
sudo rm -f /etc/apt/sources.list.d/kubernetes*.list
# The following sed command attempts to remove lines referencing old Kubernetes package sources
# from any .list files in /etc/apt/sources.list.d/ and the main /etc/apt/sources.list file.
# The || true ensures that the script doesn't exit if these patterns are not found.
sudo sed -i.bak -E '/(packages\.cloud\.google\.com\/apt|apt\.kubernetes\.io|kubernetes-xenial)/d' \
  /etc/apt/sources.list.d/*.list /etc/apt/sources.list 2>/dev/null || true


# 3) Add new key for pkgs.k8s.io
echo "Adding Kubernetes GPG key..."
sudo mkdir -p /etc/apt/keyrings
# Remove the key file if it exists to ensure non-interactive overwrite
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# Download the public signing key for the new community-owned repositories
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$STABLE/deb/Release.key" \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg # Ensure the key is readable

# 4) Add new repo for pkgs.k8s.io
echo "Adding Kubernetes APT repository..."
# Define the repository source
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$STABLE/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 5) Install kubectl
echo "Updating package lists and installing kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubectl

# 6) Verify
echo
echo "Verifying kubectl client version:"
# The --short flag was removed in kubectl v1.24. Use 'kubectl version --client' instead.
kubectl version --client
echo
echo "✅ kubectl installed!"
echo "ℹ️ Note: The STABLE version used was $STABLE. Please ensure this is the desired version for your needs."