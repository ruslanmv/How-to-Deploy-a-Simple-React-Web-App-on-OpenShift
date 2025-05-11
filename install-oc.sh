#!/bin/bash

set -e

# Define download URL for the latest oc CLI
OC_URL="https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz"

echo "🔄 Downloading oc CLI from: $OC_URL"
curl -LO "$OC_URL"

echo "📦 Extracting oc.tar.gz..."
tar -xvzf oc.tar.gz

echo "🚚 Moving oc binary to /usr/local/bin..."
sudo mv oc /usr/local/bin/

echo "🧹 Cleaning up..."
rm -f oc.tar.gz
rm -f README.md || true  # Some versions include a README

echo "✅ Verifying oc installation..."
if command -v oc >/dev/null 2>&1; then
    oc version --client
    echo "🎉 'oc' CLI installed successfully!"
else
    echo "❌ Installation failed: 'oc' command not found"
    exit 1
fi
