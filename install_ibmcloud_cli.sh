#!/usr/bin/env bash

# Script to install the IBM Cloud CLI on Linux

# Exit immediately if a command exits with a non-zero status.
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if a dpkg package is installed (for curl check on Debian/Ubuntu)
package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

echo "🚀 Attempting to install IBM Cloud CLI..."
echo "----------------------------------------"

if command_exists ibmcloud; then
    echo "✅ IBM Cloud CLI is already installed."
    ibmcloud --version
    echo "----------------------------------------"
    echo "If you wish to update it, you can often use: ibmcloud update"
    exit 0
fi

echo "IBM Cloud CLI not found. Proceeding with installation."
echo ""

# Ensure curl is installed, as it's needed to download the installer
if ! command_exists curl; then
    echo "curl command not found. Attempting to install curl..."
    if command_exists apt-get; then
        echo "Updating package lists (apt-get)..."
        sudo apt-get update -y
        echo "Installing curl..."
        sudo apt-get install -y curl
        if ! command_exists curl; then
            echo "❌ Failed to install curl. Please install curl manually and try again."
            exit 1
        fi
        echo "✅ curl installed successfully."
    else
        echo "❌ apt-get not found. Cannot automatically install curl."
        echo "Please install curl manually and try again."
        exit 1
    fi
else
    echo "✅ curl is already available."
fi
echo "----------------------------------------"

# Install IBM Cloud CLI
# The official installer script from IBM handles the installation details.
# It typically installs to /usr/local/bin/ibmcloud and may prompt for sudo if not run as root.
# Piping to 'sudo sh' ensures the script has necessary permissions for system-wide install.
echo "➡️ Downloading and running the IBM Cloud CLI installer..."
echo "This may take a few moments and might require sudo password if not already root."

if curl -fsSL https://clis.cloud.ibm.com/install/linux | sudo sh; then
    echo "✅ IBM Cloud CLI installation script executed."
else
    echo "❌ IBM Cloud CLI installation script failed to execute properly."
    exit 1
fi
echo "----------------------------------------"

# Verify installation
echo "➡️ Verifying IBM Cloud CLI installation..."
if command_exists ibmcloud; then
    echo "✅ IBM Cloud CLI installed successfully!"
    ibmcloud --version
    echo "----------------------------------------"
    echo "Next steps:"
    echo "1. Log in to IBM Cloud: ibmcloud login -a https://cloud.ibm.com"
    echo "   (or ibmcloud login --sso if you use a federated ID)"
    echo "2. Install any necessary plugins, e.g., for Container Registry:"
    echo "   ibmcloud plugin install container-registry -r 'IBM Cloud'"
else
    echo "❌ IBM Cloud CLI installation failed or it's not in PATH."
    echo "   Please check the output above for errors or try manual installation from:"
    echo "   https://cloud.ibm.com/docs/cli?topic=cli-install_cli"
    exit 1
fi

echo "🎉 IBM Cloud CLI setup script finished."