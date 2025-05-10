#!/usr/bin/env bash

# Script to setup development environment on Ubuntu 22.04+
# Installs: curl, gnupg, Docker CE, Node.js (v20.x LTS) & npm

# Exit on any error
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a dpkg package is installed (more reliable for apt packages)
package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

echo "🚀 Starting Environment Setup for Ubuntu 22.04+ 🚀"
echo "----------------------------------------"

# --- Update package lists ---
echo "➡️ Updating package lists..."
sudo apt-get update -y
echo "✅ Package lists updated."
echo "----------------------------------------"

# --- Install basic utilities (curl, gnupg) ---
echo "➡️ Checking/Installing basic utilities (curl, gnupg)..."

if ! package_installed curl; then
    echo "Installing curl..."
    sudo apt-get install -y curl
    echo "✅ curl installed."
else
    echo "✅ curl is already installed."
fi

if ! package_installed gnupg; then
    echo "Installing gnupg..."
    sudo apt-get install -y gnupg
    echo "✅ gnupg installed."
else
    echo "✅ gnupg is already installed."
fi
echo "----------------------------------------"

# --- Install Docker CE ---
echo "➡️ Checking/Installing Docker CE..."
if command_exists docker; then
    echo "✅ Docker appears to be installed."
    docker --version
else
    echo "Installing Docker CE..."
    # Install prerequisites for adding Docker repo
    sudo apt-get install -y ca-certificates # curl is already handled

    # Add Docker's official GPG key:
    echo "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    # Remove old key if it exists to avoid conflicts with the new .asc format
    if [ -f /etc/apt/keyrings/docker.gpg ]; then
        echo "Removing old docker.gpg key..."
        sudo rm /etc/apt/keyrings/docker.gpg
    fi
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the Docker repository to Apt sources:
    echo "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "Updating package lists after adding Docker repo..."
    sudo apt-get update -y

    echo "Installing Docker CE packages..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "✅ Docker CE installed."
    docker --version

    echo "ℹ️ To run Docker commands without sudo, you can add your user to the 'docker' group:"
    echo "   sudo usermod -aG docker $USER"
    echo "   Then, you MUST log out and log back in for the group changes to take effect."
fi
echo "----------------------------------------"

# --- Install Node.js (e.g., v20.x LTS) and npm using NodeSource ---
NODE_MAJOR_VERSION="20" # Current LTS version as of early 2024, satisfies "v16+"
echo "➡️ Checking/Installing Node.js v${NODE_MAJOR_VERSION}.x and npm..."

# Check if node is installed and if it's the target major version
NODE_INSTALLED_CORRECT_VERSION=false
if command_exists node; then
    CURRENT_NODE_VERSION=$(node -v)
    if [[ "$CURRENT_NODE_VERSION" == "v${NODE_MAJOR_VERSION}"* ]]; then
        NODE_INSTALLED_CORRECT_VERSION=true
        echo "✅ Node.js v${NODE_MAJOR_VERSION}.x is already installed."
        node -v
        npm -v
    else
        echo "ℹ️ An existing Node.js version is installed ($CURRENT_NODE_VERSION), but it's not v${NODE_MAJOR_VERSION}.x."
        echo "    If you need Node.js v${NODE_MAJOR_VERSION}.x specifically, consider using a version manager like 'nvm'"
        echo "    or uninstalling the current version before running this script again."
        echo "    Skipping Node.js v${NODE_MAJOR_VERSION}.x installation to avoid conflict."
    fi
else
    echo "Node.js not found."
fi


if ! $NODE_INSTALLED_CORRECT_VERSION && ! (command_exists node && [[ "$(node -v)" != "v${NODE_MAJOR_VERSION}"* ]]); then
    echo "Installing Node.js v${NODE_MAJOR_VERSION}.x and npm via NodeSource..."
    # Ensure curl is available (should be from earlier step)
    if ! command_exists curl; then
        echo "Error: curl is required for NodeSource setup but not found." >&2
        exit 1
    fi

    echo "Downloading and running NodeSource setup script for Node.js v${NODE_MAJOR_VERSION}.x..."
    # The NodeSource script adds the GPG key and repository.
    # Running with sudo -E to preserve environment variables like HOME, which some scripts might need.
    curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | sudo -E bash -

    echo "Updating package lists after adding NodeSource repo..."
    sudo apt-get update -y # Though NodeSource script might do this

    echo "Installing nodejs package..."
    sudo apt-get install -y nodejs # This will install Node.js and npm

    echo "✅ Node.js v${NODE_MAJOR_VERSION}.x and npm installed."
    node -v
    npm -v
fi
echo "----------------------------------------"

echo "🎉 Environment setup script finished successfully! 🎉"
echo "REMINDERS:"
echo "  - For Docker: If you added your user to the 'docker' group, log out and log back in."
echo "  - For Node.js: If you had a different version, this script attempted to avoid conflicts. Manage Node.js versions using 'nvm' (Node Version Manager) for more flexibility if needed."
echo "----------------------------------------"