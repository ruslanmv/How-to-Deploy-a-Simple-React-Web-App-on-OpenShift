
# How to Deploy a Simple React Web App on OpenShift 
Goal: Create a “Hello, world!” React app → Dockerize it → Push to a registry → Import & run it on OpenShift’s Developer Console.

![](assets/2025-05-10-19-33-16.png)

This guide provides a comprehensive walkthrough for deploying a React web application to Red Hat OpenShift on IBM Cloud , covering environment setup on WSL/Ubuntu, `kubectl` installation, application scaffolding, Dockerization, image management, and deployment using both the OpenShift Web Console and `kubectl` CLI.

**Target OpenShift Environment (from initial context):**

* **Platform:** Red Hat OpenShift Container Platform
* **Console:** `https://console-openshift-console.roks-demo`
* **Project Example:** `ibmid-667000nwl8-xxxx` (Ensure you are targeting your correct project in OpenShift)

## 📋 Table of Contents

1.  Environment Setup (WSL/Ubuntu)
2.  Installing `kubectl` on Ubuntu/WSL
3.  Scaffolding a Simple React App
4.  Dockerizing the React App
5.  Building & Pushing the Image
6.  Deploying on OpenShift (Web Console)
7.  Alternative: Deploy via `kubectl` CLI
8.  Verification & Next Steps
9.  Improvements & Enhancements




## 1. Environment Setup (WSL/Ubuntu)

Before we begin, ensure you have a clean Ubuntu 22.04+ environment. This could be on Windows Subsystem for Linux (WSL), a Virtual Machine (VM), or a bare-metal installation. The key requirements are:

* `sudo` privileges to install software.
* Essential command-line tools: `bash`, `curl`, `gnupg`.
* **Docker Engine:** We'll be containerizing our React app. Docker CE (Community Edition) should be installed from the [official Docker repository](https://docs.docker.com/engine/install/ubuntu/).
* **Node.js & npm:** For creating and building the React application. A Node.js version of v16 or higher is recommended. We'll use NodeSource distributions for installation. `npm` (Node Package Manager) is typically included with Node.js. (Yarn is an alternative package manager, but this guide will focus on npm).

To help automate the setup of `curl`, `gnupg`, Docker, and Node.js/npm, you can use the script below.

**Automated Setup Script (`setup_dev_env.sh`):**

You can save the following bash script to a file (e.g., `setup_dev_env.sh`), make it executable (`chmod +x setup_dev_env.sh`), and then run it with `sudo ./setup_dev_env.sh`.

```bash
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
    echo "   sudo usermod -aG docker \$USER" # Escaped $USER for correct display in script
    echo "   Then, you MUST log out and log back in for the group changes to take effect."
fi
echo "----------------------------------------"

# --- Install Node.js (e.g., v20.x LTS) and npm using NodeSource ---
NODE_MAJOR_VERSION="20" # Current LTS version as of early 2024, satisfies "v16+"
echo "➡️ Checking/Installing Node.js v\${NODE_MAJOR_VERSION}.x and npm..." # Escaped ${NODE_MAJOR_VERSION}

# Check if node is installed and if it's the target major version
NODE_INSTALLED_CORRECT_VERSION=false
if command_exists node; then
    CURRENT_NODE_VERSION=\$(node -v) # Escaped $()
    if [[ "\$CURRENT_NODE_VERSION" == "v\${NODE_MAJOR_VERSION}"* ]]; then # Escaped variables
        NODE_INSTALLED_CORRECT_VERSION=true
        echo "✅ Node.js v\${NODE_MAJOR_VERSION}.x is already installed." # Escaped
        node -v
        npm -v
    else
        echo "ℹ️ An existing Node.js version is installed (\$CURRENT_NODE_VERSION), but it's not v\${NODE_MAJOR_VERSION}.x." # Escaped
        echo "    If you need Node.js v\${NODE_MAJOR_VERSION}.x specifically, consider using a version manager like 'nvm'" # Escaped
        echo "    or uninstalling the current version before running this script again."
        echo "    Skipping Node.js v\${NODE_MAJOR_VERSION}.x installation to avoid conflict." # Escaped
    fi
else
    echo "Node.js not found."
fi


if ! \$NODE_INSTALLED_CORRECT_VERSION && ! (command_exists node && [[ "\$(node -v)" != "v\${NODE_MAJOR_VERSION}"* ]]); then # Escaped
    echo "Installing Node.js v\${NODE_MAJOR_VERSION}.x and npm via NodeSource..." # Escaped
    # Ensure curl is available (should be from earlier step)
    if ! command_exists curl; then
        echo "Error: curl is required for NodeSource setup but not found." >&2
        exit 1
    fi

    echo "Downloading and running NodeSource setup script for Node.js v\${NODE_MAJOR_VERSION}.x..." # Escaped
    # The NodeSource script adds the GPG key and repository.
    # Running with sudo -E to preserve environment variables like HOME, which some scripts might need.
    curl -fsSL https://deb.nodesource.com/setup_\${NODE_MAJOR_VERSION}.x | sudo -E bash - # Escaped

    echo "Updating package lists after adding NodeSource repo..."
    sudo apt-get update -y # Though NodeSource script might do this

    echo "Installing nodejs package..."
    sudo apt-get install -y nodejs # This will install Node.js and npm

    echo "✅ Node.js v\${NODE_MAJOR_VERSION}.x and npm installed." # Escaped
    node -v
    npm -v
fi
echo "----------------------------------------"

echo "🎉 Environment setup script finished successfully! 🎉"
echo "REMINDERS:"
echo "  - For Docker: If you added your user to the 'docker' group, log out and log back in."
echo "  - For Node.js: If you had a different version, this script attempted to avoid conflicts. Manage Node.js versions using 'nvm' (Node Version Manager) for more flexibility if needed."
echo "----------------------------------------"

```
**To use the script:**
1.  Copy the entire block of code above, starting with `#!/usr/bin/env bash` and ending with the last `echo "----------------------------------------"`.
2.  Paste it into a new file in your Ubuntu environment. Name the file `setup_dev_env.sh`.
3.  Open a terminal, navigate to the directory where you saved the file, and make it executable:
    ```bash
    chmod +x setup_dev_env.sh
    ```
4.  Run the script with sudo privileges:
    ```bash
    sudo ./setup_dev_env.sh
    ```
This script will guide you through the installation of the necessary prerequisites.

![](assets/2025-05-10-15-17-51.png)

Once these tools are in place, you’ll also need `kubectl` to talk to your ROKS cluster. The next section covers its installation.

## 2. Installing `kubectl` on Ubuntu/WSL

Save this as `install_kubectl_ubuntu.sh`, then run it to:

* Remove old `kubernetes-xenial` repos
* Point at `pkgs.k8s.io`
* Install & verify `kubectl`

```bash
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
````

Make the script executable and run it:

```bash
chmod +x install_kubectl_ubuntu.sh
./install_kubectl_ubuntu.sh
```

![](assets/2025-05-10-15-16-15.png)


## We are going to push our image in a IBM cloud 
install_ibmcloud_cli.sh

```bash
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
```

![](assets/2025-05-10-15-42-59.png)

## 3\. Scaffolding a Simple React App

Let's create a basic React application.

```bash
npx create-react-app hello-react
cd hello-react
```

Now, edit `src/App.js` to display a simple message:

```javascript
// src/App.js
import React from 'react';

function App() {
  return (
    <div style={{
      fontSize: '2rem',
      textAlign: 'center',
      padding: '2rem',
      fontFamily: 'sans-serif'
    }}>
      <h1>Hello, world!</h1>
      <p>Your React app is now running in OpenShift ROKS.</p>
    </div>
  );
}

export default App;
```

You can test it locally:

```bash
npm start
```
![](assets/2025-05-10-15-29-21.png)
Open `http://localhost:3000` in your browser.

![](assets/2025-05-10-15-23-11.png)



---

## 4. Dockerizing the React App

In your `hello-react/` directory, create a `Dockerfile` (no extension) with the following content. We’ve switched to the official **unprivileged** NGINX image so it:

* Runs as a non-root user (OpenShift arbitrary UID–safe)
* Listens on port `8080` (avoiding privileged ports <1024)
* Doesn’t try to patch a read-only `/etc/nginx` at startup

```dockerfile
# hello-react/Dockerfile

# --------------------------
# 1. Build stage (Node.js)
# --------------------------
FROM node:23-alpine AS builder
WORKDIR /app

# Install dependencies exactly as in lockfile
COPY package*.json ./
RUN npm ci

# Copy source & build static assets
COPY . .
RUN npm run build

# --------------------------
# 2. Production stage (NGINX)
# --------------------------
FROM nginxinc/nginx-unprivileged:stable-alpine

# Copy built React app into NGINX’s html folder
COPY --from=builder /app/build /usr/share/nginx/html

# OpenShift will mount this image read-only, but nginx-unprivileged
# already runs as a non-root user (UID 101) and listens on 8080.
EXPOSE 8080

# Run NGINX in the foreground
CMD ["nginx", "-g", "daemon off;"]
```

### Explanation 

* **`nginxinc/nginx-unprivileged:stable-alpine`**

  * Runs as a non-root user by default (OpenShift arbitrary UIDs won’t need `anyuid` SCC).
  * Listens on port **8080**, so you avoid the bind-to-80 “Permission denied” error.
  * No more IPv6 patch script failures on a read-only filesystem.

* **Port mapping**

  * Internally listens on **8080**, but externally you can map it to 80/443 via your Service/Route.

---

## 5. Local Run Sanity Check

Before pushing to OpenShift, verify it works locally:

```bash
# Build and tag
docker build -t ruslanmv/hello-react:1.0.0 .

# Run and map port 8080 → 8080
docker run --rm -p 8080:8080 ruslanmv/hello-react:1.0.0
```

Visit [http://localhost:8080](http://localhost:8080) and you should see your “Hello, world!” page—no permission or filesystem errors in the logs.

---


## 5\. Building & Pushing the Image to IBM Cloud Container Registry

With your `hello-react` application Dockerized, the next step is to build the image and push it to a container registry. This makes the image accessible for deployment to your OpenShift cluster. We will focus on using the **IBM Cloud Container Registry (ICR)**.

Let's get started by installing the necessary CLIs (if you haven't already), setting up your first private registry namespace in ICR, and then pushing your `hello-react` image.

**A. Prerequisites: Setting up IBM Cloud CLI and Container Registry**

1.  **Install the IBM Cloud CLI:**
    If you don't have it installed, follow the [official instructions](https://www.google.com/search?q=https://cloud.ibm.com/docs/cli%3Ftopic%3Dcli-install_cli). For Linux, a common method is:

    ```bash
    curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
    ```

    Verify the installation:

    ```bash
    ibmcloud --version
    ```

2.  **Install the Docker CLI:**
    The Docker CLI should already be installed if you used the environment setup script from **Section 1**. If not, please ensure Docker is installed and running.

3.  **Install the Container Registry Plug-in:**
    This plug-in extends the IBM Cloud CLI with commands for ICR.

    ```bash
    ibmcloud plugin install container-registry -r 'IBM Cloud'
    ```

    If it's already installed, you can update it using `ibmcloud plugin update container-registry`.

4.  **Log in to your IBM Cloud Account:**

    ```bash
    ibmcloud login -a https://cloud.ibm.com
    ```

    If you have a federated ID, use `ibmcloud login --sso`. Follow the prompts to complete the login.

5.  **Set Your Target IBM Cloud Container Registry Region:**
    Ensure you're targeting the correct region where you want to host your images. For example, to target US South:

    ```bash
    ibmcloud cr region-set us-south
    ```

    To see available regions, use `ibmcloud cr regions`.

6.  **Create a Namespace in IBM Cloud Container Registry:**
    A namespace provides a unique space for your images within a region. Choose a unique name for your namespace. This namespace will be part of your image URL.

    ```bash
    ibmcloud cr namespace-add <my_namespace>
    ```

    Replace `<my_namespace>` with your chosen namespace. For example, if your project or organization uses a specific naming convention like `cc-667000nwl8-n8918mfv-cr`, you would use:

    ```bash
    ibmcloud cr namespace-add cc-667000nwl8-n8918mfv-cr
    ```

    Verify the namespace is added: `ibmcloud cr namespace-list`.

**B. Building Your `hello-react` Docker Image**

Now, navigate to your `hello-react` project directory (the one containing your `Dockerfile`). Build the Docker image, tagging it directly with the IBM Cloud Container Registry path. This path will be `REGISTRY_HOSTNAME/<my_namespace>/<repository_name>:<tag>`.

For ICR in US South, the `REGISTRY_HOSTNAME` is `us.icr.io`.

1.  **Build and Tag the Image for ICR:**
    Replace `<my_namespace>` with the namespace you created in the previous step. We'll use `hello-react` as the repository name and `1.0.0` as the tag.
    ```bash
    docker build -t us.icr.io/<my_namespace>/hello-react:1.0.0 .
    ```
    For example, using the specific namespace format from your context:
    ```bash
    docker build -t us.icr.io/cc-667000nwl8-n8918mfv-cr/hello-react:1.0.0 .
    ```

**C. Pushing the Image to Your Private ICR Namespace**

1.  **Log Your Local Docker Daemon into IBM Cloud Container Registry:**
    This command uses your IBM Cloud CLI session to authenticate Docker.

    ```bash
    ibmcloud cr login
    ```

    If successful, you'll see a "Logged in\!" message.

2.  **Push the Image to ICR:**
    Use the same image name you used in the `docker build` command.

    ```bash
    docker push us.icr.io/<my_namespace>/hello-react:1.0.0
    ```

    For the specific example:

    ```bash
    docker push us.icr.io/cc-667000nwl8-n8918mfv-cr/hello-react:1.0.0
    ```

3.  **Verify Your Image is in Your Private Registry:**
    You can list images in your namespace using the IBM Cloud CLI:

    ```bash
    ibmcloud cr image-list --restrict <my_namespace>
    ```

    Or, to see all images you have access to (if you omit `--restrict`):

    ```bash
    ibmcloud cr image-list
    ```

    You should see `us.icr.io/<my_namespace>/hello-react` with the tag `1.0.0` listed.

Your `hello-react` image, for instance `us.icr.io/cc-667000nwl8-n8918mfv-cr/hello-react:1.0.0`, is now stored in your private IBM Cloud Container Registry and is ready to be deployed to OpenShift\!



*(Optional: Alternative - Docker Hub)*

*If you prefer to use Docker Hub:*

1.  *Build: `docker build -t YOUR_DOCKERHUB_USERNAME/hello-react:1.0.0 .`*
2.  *Login: `docker login` (enter your Docker Hub credentials)*
3.  *Push: `docker push YOUR_DOCKERHUB_USERNAME/hello-react:1.0.0`*



Or you can use the our script [build_and_push_icr.sh](build_and_push_icr.sh) you copy where the Dockerfile it is.


![](assets/2025-05-10-16-31-17.png)


## 6. Deploying on OpenShift (Web Console)

Once your `hello-react` application is containerized and the image is available in a container registry, you can deploy it to your OpenShift on ROKS cluster using the web console. This section will guide you through deploying your image using two common scenarios: from a private registry like IBM Cloud Container Registry (ICR) and from a public registry like Docker Hub.

**A Note on Resource Quotas:**
Your OpenShift project likely has ResourceQuotas in place. This means that when you deploy an application, you **must** specify **Resource Requests** (the amount of CPU/memory guaranteed to your container) and **Resource Limits** (the maximum amount of CPU/memory your container can use). If these are not defined, your deployment will be rejected with a "failed quota" error, similar to the one you encountered. We will cover setting these in the steps below.

**Initial Steps in the OpenShift Web Console:**

1.  **Log in to your ROKS console** and ensure you are in the **Developer** perspective.
2.  Navigate to your target **Project** from the project dropdown list.
3.  In the left navigation pane, click the **`+Add`** button.

From here, the steps will diverge slightly based on whether your image is in a private or public registry.

---

### Method A: Deploying from a Private Registry (e.g., IBM Cloud Container Registry - ICR)

Private container registries require authentication. If you haven't already configured an Image Pull Secret for your ICR namespace in this OpenShift project, please refer to the troubleshooting steps at the end of this "Method A" section.

**Image to Deploy (Example for ICR):**
`us.icr.io/cc-667000nwl8-n8918mfv-cr/hello-react:1.0.0`

**🚀 Deploying Your Application from ICR**

1.  **Navigate to Add Application**:
    * After the initial steps (logged in, correct project, click `+Add`), choose **"Container Image"**.
![](assets/2025-05-10-19-52-12.png)


    
2.  **Fill in the Image Details**:
    * **Image name from external registry**: Enter the full path to your image in ICR:
        `us.icr.io/cc-667000nwl8-n8918mfv-cr/hello-react:1.0.0`
3.  **Configure Application, Deployment, and Resource Limits**:
    * **Application Name**: e.g., `hello-react-icr-app`.
    * **Name** (for Deployment resource): e.g., `hello-react-icr`.
    * **Runtime icon**: Choose an appropriate icon.
    * **Labels**: Add any desired labels.
    * **Setting Resource Requests and Limits (Crucial for Quotas):**
        * Look for a section typically labeled **"Resource Limits"**, **"Compute Resources"**, or sometimes under "Advanced options" or "Scaling".
        * You will need to set values for:
            * **CPU Request**: The minimum amount of CPU guaranteed to the container.
            * **CPU Limit**: The maximum amount of CPU the container can use.
            * **Memory Request**: The minimum amount of memory guaranteed to the container.
            * **Memory Limit**: The maximum amount of memory the container can use.
        * **Example Values (Adjust as Needed):**
            * *CPU Request:* `1` (unit is typically cores, e.g., `1` for 1 core, `0.5` or `500m` for half a core)
            * *CPU Limit:* `4` (cores)
            * *Memory Request:* `64Mi` (Mebibytes)
            * *Memory Limit:* `128Mi` (Mebibytes)
            **❗ Important Advisory on Example Values:** The values above (`CPU Request: 1 core`, `CPU Limit: 4 cores`, `Memory Request: 64Mi`, `Memory Limit: 128Mi`) are provided as per your request for an example. While `64Mi/128Mi` for memory is a reasonable starting point for a very simple web application, a CPU request of `1 core` and a limit of `4 cores` is quite generous for a basic "Hello World" React app served by Nginx and might be more than needed or available under your project's quota for such a simple app.
            **Recommended Action:** Always start with values that you believe are reasonable for your application's typical load and then **monitor its actual resource consumption** in OpenShift. Adjust these requests and limits based on observed performance and the specific quotas enforced in your project. Setting requests appropriately helps Kubernetes schedule your pods efficiently, while limits prevent a single container from starving other applications on the same node.
4.  **Configure Routing / Networking**:
    * Ensure **`Create a route to the Application`** is checked.
    * **Target port**: For the Nginx-served React app, this is `80`.
5.  **Create the Application**:
    * Review your settings and click **"Create"**.

**🔐 Troubleshooting ICR: Authorization & Image Pull Secrets (If not done already)**

If, after clicking "Create", your Pods are stuck with `ImagePullBackOff` or `ErrImagePull`, or you get an authorization error *before* the quota error, it means OpenShift cannot authenticate with your private ICR. You need an Image Pull Secret.

* **Step 1: Create an IBM Cloud IAM API Key** (if you don't have one for this purpose).
* **Step 2: Create the Image Pull Secret in OpenShift (via Web Console UI as you detailed previously):**
    1.  Navigate to **Workloads > Secrets**.
    2.  Click **Create > Image Pull Secret**.
    3.  **Secret Name**: e.g., `ibm-cr-pull-secret`.
    4.  **Authentication Type**: `Image Registry Credentials`.
    5.  **Registry Server Address**: `us.icr.io` (or your ICR region's hostname).
    6.  **Username**: `iamapikey`.
    7.  **Password**: Your IBM Cloud IAM API key.
    8.  **Email**: e.g., `user@example.com`.
    9.  Click **Create**.
* **Step 3: Link Secret to Default Service Account (via Web Console UI as you detailed):**
    1.  Navigate to **User Management > ServiceAccounts**.
    2.  Select the `default` service account.
    3.  Go to the **YAML** tab.
    4.  Add/update the `imagePullSecrets` section:
        ```yaml
        imagePullSecrets:
          - name: ibm-cr-pull-secret # Use your secret name
        ```
    5.  Click **Save**.

After setting up the pull secret and resource limits, your deployment from ICR should proceed.

---

### Method B: Deploying from a Public Registry (e.g., Docker Hub)

Deploying a **public** image from Docker Hub is generally simpler as it usually doesn't require pull secrets. However, you **still need to set resource requests and limits** if your project has quotas.

**Image to Deploy (Example for Docker Hub):**
`docker.io/ruslanmv/hello-react:1.0.0` (or `ruslanmv/hello-react:1.0.0`)

**🚀 Deploying Your Application from Docker Hub**

1.  **Navigate to Add Application**:
    * After the initial steps (logged in, correct project, click `+Add`), choose **"Container Image"**.
2.  **Fill in the Image Details**:
    * **Image name from external registry**: Enter the path to your public Docker Hub image:
        `docker.io/ruslanmv/hello-react:1.0.0`
![](assets/2025-05-10-19-53-05.png)

3.  **Configure Application, Deployment, and Resource Limits**:
    * **Application Name**: e.g., `hello-react-dockerhub-app`.
    * **Name** (for Deployment resource): e.g., `hello-react-dockerhub`.
    * **Runtime icon**: Choose an appropriate icon.
    * **Setting Resource Requests and Limits (Crucial for Quotas):**
        * As in Method A, find the **"Resource Limits"** or **"Compute Resources"** section.
        * Set appropriate values for CPU Request, CPU Limit, Memory Request, and Memory Limit.
        * **Example values (Adjust as Needed):**
            * *CPU Request:* `1` (core)
            * *CPU Limit:* `2` (cores)
            * *Memory Request:* `128Mi`
            * *Memory Limit:* `256Mi`
        * **❗ Reminder:** The CPU values (`1 core` request, `2 cores` limit) are generous for a simple demo. Adjust all these values based on your application's actual needs and your project's available quotas.
![](assets/2025-05-10-19-55-22.png)

4.  **Configure Routing / Networking**:
    * Ensure **`Create a route to the Application`** is checked.
    * **Target port**: `80`.
5.  **Create the Application**:
    * Click **"Create"**.


![](assets/2025-05-10-19-28-14.png)


**🔐 (Optional) For Private Images on Docker Hub:**

If your image on Docker Hub were **private**, you would:
1.  Create an Image Pull Secret (similar to ICR: Workloads > Secrets > Create > Image Pull Secret) with:
    * **Secret Name**: e.g., `dockerhub-pull-secret`.
    * **Registry Server Address**: `https://index.docker.io/v1/` (or `docker.io`).
    * **Username**: Your Docker Hub username.
    * **Password**: Your Docker Hub password or a Personal Access Token (PAT).
    * **Email**: Your Docker Hub email.
2.  Link this `dockerhub-pull-secret` to the `default` service account (User Management > ServiceAccounts > default > YAML).

---

### Common Next Steps (After Successful Deployment)

Regardless of the method used, once you click "Create" and have correctly configured image pull secrets (if needed) and resource limits:

1.  **Monitor Deployment Progress**:
    * Go to the **Topology** view. Your new application should appear.
    * Click on it to see Pods transitioning from `Pending`/`ContainerCreating` to `Running`. If they get stuck, check Pod events (`oc describe pod <pod-name> -n <project>` or via the UI) for errors related to quotas or image pulls.

2.  **Access Your Application**:
    * Once the Pod is `Running`, find the Route URL (from Topology view's "Open URL" icon, or under "Networking" > "Routes").
    * Click the URL to see your `hello-react` app.

This revised section now uses your specified example values for CPU and Memory requests/limits, along with the necessary context and advice for adjusting them.
![](assets/2025-05-10-19-29-02.png)
### Alternative via Web Console: Using a BuildConfig (from Dockerfile in Git)

If your code (including the `Dockerfile`) is in a Git repository and you want OpenShift to build  "Create BuildConfig":

1.  Click **`+Add`**.
2.  Choose **`From Git`**.
3.  Enter your Git Repository URL.
4.  OpenShift usually detects the Dockerfile. If not, you might need to specify the "Dockerfile" strategy under advanced options.
5.  Configure the application name, resource name, and ensure "Create a route" is selected.
6.  OpenShift will create a `BuildConfig`, an `ImageStream`, build the image, and then deploy it. You can find the "Create BuildConfig" form  if you navigate through "Builds" -\> "BuildConfigs" -\> "Create BuildConfig" or if this option appears in the `+Add` flow for more advanced Git import scenarios.
      * **Screenshot Context :** The fields visible in your screenshot ("Name", "Source type", "Images - Build from", "Push to") are part of the `BuildConfig` creation. If you select "Git Repository" as `Source type`, you provide the Git URL. "Push to" would typically be an "Image Stream Tag" within OpenShift.



## 7\. Alternative: Deploy via `kubectl` CLI

First, ensure `kubectl` is configured to communicate with your ROKS cluster. You typically download the `kubeconfig` file from the IBM Cloud console for your cluster and set the `KUBECONFIG` environment variable or merge it into your default `~/.kube/config`.

```bash
export KUBECONFIG=/path/to/your/downloaded.kubeconfig
kubectl get nodes # Test connectivity
```

Create the following YAML files in your `hello-react` project directory. Remember to replace `ruslanmv/hello-react:1.0.0` with your actual image path.

**`deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-react
  namespace: ibmid-667000nwl8-hktijvj4 # Or your desired namespace
  labels:
    app: hello-react
    app.kubernetes.io/component: hello-react
    app.kubernetes.io/instance: hello-react
    app.kubernetes.io/name: hello-react
    app.kubernetes.io/part-of: hello-react-app
    # app.openshift.io/runtime-version: 1.0.0 # This label was on the Route, can be added here too if desired
    # app.openshift.io/runtime-namespace: ibmid-667000nwl8-hktijvj4 # This is usually for internal OpenShift use
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-react
  template:
    metadata:
      labels:
        app: hello-react
        deployment: hello-react # Connects to the selector in the Service
      # annotations:
        # openshift.io/generated-by: kubectl # Optional: indicate how it was created
    spec:
      containers:
        - name: hello-react
          image: docker.io/ruslanmv/hello-react:1.0.0 # Your specified Docker image
          ports:
            - containerPort: 8080
              protocol: TCP
          resources:
            limits:
              cpu: '2'
              memory: 256Mi
            requests:
              cpu: '1'
              memory: 128Mi
          imagePullPolicy: IfNotPresent # Or Always, if you want to ensure the latest image version is pulled every time
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      securityContext: {}
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
```

**`service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-react
  namespace: ibmid-667000nwl8-hktijvj4
  labels:
    app: hello-react
    app.kubernetes.io/component: hello-react
    app.kubernetes.io/instance: hello-react
    app.kubernetes.io/name: hello-react
    app.kubernetes.io/part-of: hello-react-app
spec:
  selector:
    app: hello-react
  ports:
    - name: http-8080 # Explicitly name the port
      protocol: TCP
      port: 8080       # Service port
      targetPort: 8080   # Container port
  type: ClusterIP
```

**`route.yaml` (OpenShift Specific)**
For standard Kubernetes Ingress, you would use an `Ingress` resource. OpenShift uses `Route`.

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello-react
  namespace: ibmid-667000nwl8-hktijvj4
  labels:
    app: hello-react
    app.kubernetes.io/component: hello-react
    app.kubernetes.io/instance: hello-react
    app.kubernetes.io/name: hello-react
    app.kubernetes.io/part-of: hello-react-app
    app.openshift.io/runtime-version: "1.0.0"
  annotations:
    openshift.io/host.generated: "true"
spec:
  port:
    targetPort: http-8080 # Reference the named port from the Service
  to:
    kind: Service
    name: hello-react
    weight: 100
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```


**Deployment**

**Step 1: Ensure kubectl is Configured and Pointing to the Correct Namespace**

If you haven't already, ensure your `kubectl` context is targeting the intended OpenShift cluster and namespace.

```bash
# Check current context
kubectl config current-context

# List available contexts
kubectl config get-contexts

# Switch to the correct context if needed
# kubectl config use-context <your-openshift-context-name>

# Set the default namespace for subsequent commands (optional, but helpful)
# Replace 'ibmid-667000nwl8-hktijvj4' with your target namespace
kubectl config set-context --current --namespace=ibmid-667000nwl8-hktijvj4

# If the namespace doesn't exist, create it (if you haven't already and it's not a pre-existing project)
# kubectl create namespace ibmid-667000nwl8-hktijvj4
```

**Step 2: Apply the `deployment.yaml` File**

This command tells OpenShift to create or update the Deployment resource according to your `deployment.yaml` file. This will start pulling the Docker image and creating the pods.

```bash
kubectl apply -f deployment.yaml
```

* You'll see output like: `deployment.apps/hello-react configured`.
* The warning about the `last-applied-configuration` annotation is expected if this is the first `apply` for this resource (or if it was previously created differently) and is automatically handled by `kubectl`.

**Step 3: Apply the `service.yaml` File**

This command creates the Service resource, which provides an internal network endpoint (IP address and port) for your application pods.

```bash
kubectl apply -f service.yaml
```

* You'll see output like: `service/hello-react configured`.
* A similar warning about the annotation might appear here too if it's the first apply for this service, which is also normal.

**Step 4: Apply the `route.yaml` File**

This command creates the Route resource, which exposes your Service to external traffic, making your application accessible via a URL.

```bash
kubectl apply -f route.yaml
```

* You'll see output like: `route.route.openshift.io/hello-react configured`.
* Again, the annotation warning is possible and normal on the first apply.


Wait for the deployment to be ready:

```bash
kubectl rollout status deployment/hello-react
```

Get the public URL assigned by the Route:

```bash
# This command extracts the host from the route. It might take a moment for the host to be assigned.
kubectl get route hello-react -o jsonpath='{.spec.host}'
```

You should see an output like `hello-react-yourproject.yourclusterdomain.com`. Point your browser at `http://<that-host>`.



**Step 5: Verify the Deployment**

After applying all the files, check the status of your resources to ensure everything is running correctly.

* **Check Deployments:**
    ```bash
    kubectl get deployments -n ibmid-667000nwl8-hktijvj4
    ```
    *(Ensure `READY` and `AVAILABLE` columns show the desired number of replicas, e.g., `1/1`)*

* **Check Pods:**
    ```bash
    kubectl get pods -n ibmid-667000nwl8-hktijvj4 -w
    ```
    *(Watch ( `-w`) until the `hello-react` pod shows `STATUS` as `Running` and `READY` as `1/1`)*

* **Check Services:**
    ```bash
    kubectl get services -n ibmid-667000nwl8-hktijvj4
    ```
    *(Ensure the `hello-react` service has an internal `CLUSTER-IP` and the correct `PORT(S)`)*

* **Check Routes (and get the URL):**
    ```bash
    kubectl get routes -n ibmid-667000nwl8-hktijvj4
    ```
    *(This will list the route and its `HOST/PORT` which is the URL to access your application)*
    You can also get more details:
    ```bash
    kubectl describe route hello-react -n ibmid-667000nwl8-hktijvj4
    ```
    *(Look for `Status.Ingress.Host` or a similar field for the exact URL)*

**Step 6: Access Your Application**

Open the URL obtained from the `kubectl get routes` or `kubectl describe route` command in your web browser.

These are the comprehensive steps to deploy your application using `kubectl` and the provided YAML files. The key is to apply each resource definition in order (Deployment, then Service, then Route), and understand that the `kubectl apply` warning is part of its standard operation for new or unmanaged resources.

###########




## 8\. Verification & Next Steps

  * **Topology View:** In the OpenShift Web Console, the **Topology** view should now show your `hello-react` application components (Deployment, Pod, Service, Route).
  * **Access App:** Clicking the hostname provided by the Route (either from `kubectl get route` or in the console's "Routes" section or Topology view) should open your “Hello, world\!” page.

**Scale up replicas(Optional):**

```bash
kubectl scale deployment hello-react --replicas=3
```

Verify in the console or with `kubectl get pods -l app=hello-react`.

**Roll out a new version:**

1.  Make changes to your React app.
2.  Rebuild your Docker image with a new tag (e.g., `1.0.1`):
    ```bash
    docker build -t ruslanmv/hello-react:1.0.1 .
    docker push ruslanmv/hello-react:1.0.1
    ```
3.  Update the deployment to use the new image:
    ```bash
    kubectl set image deployment/hello-react hello-react=ruslanmv/hello-react:1.0.1
    # Or edit deployment.yaml and kubectl apply -f deployment.yaml
    ```
4.  Monitor the rollout:
    ```bash
    kubectl rollout status deployment/hello-react
    kubectl rollout history deployment/hello-react
    ```








Okay, here's a new blog section in Markdown format explaining how to deploy applications to OpenShift using the interactive scripts, based on the examples you provided.

```markdown
## Streamlining Your OpenShift Deployments with Interactive Scripts

Deploying applications to OpenShift involves creating several YAML configuration files for Deployments, Services, Routes, and more. While powerful, managing these files manually can be time-consuming and error-prone, especially for newcomers or when deploying frequently. To simplify this, we can use interactive shell scripts that guide you through the process, automatically generate the necessary configurations, and deploy your application.

In this section, we'll explore how to use a set of helpful scripts to:

1.  Interactively gather your application details and generate the required YAML files.
2.  Deploy your application to an OpenShift cluster.
3.  Check the status of your deployed application in detail.

Let's dive in!

### Prerequisites

Before you begin, ensure you have:

* `kubectl` command-line tool installed.
* `kubectl` configured to access your OpenShift cluster.
* The helper scripts (`build_and_deploy_kubectl.sh`, `deploy_kubectl.sh`, and `check_kubectl.sh`) available in your environment.

(Our scripts include a check for `kubectl` to ensure it's available.)

### Part 1: Generating YAMLs and Deploying with `build_and_deploy_kubectl.sh`

This script is designed to walk you through configuring your application, generate the standard Kubernetes and OpenShift YAML files (Deployment, Service, and Route), save them to a local directory, and then optionally deploy them.

**Step 1: Execute the Script**

Open your terminal and run the script:

```bash
bash build_and_deploy_kubectl.sh
```

**Step 2: Interactive Configuration**

The script will first confirm `kubectl` is found and check if you're in an OpenShift environment. Then, it will prompt you for various details about your application. You can usually accept the defaults by pressing Enter if they suit your needs.

Here’s an example of the initial interaction:

```text
[INFO] kubectl found.
[INFO] Checking for OpenShift environment...
[INFO] OpenShift environment detected (Route API available).
==============================================================
 Kubernetes/OpenShift Interactive YAML Builder & Deployer Script
==============================================================

Enter the application name (e.g., my-react-app, default: hello-react):
Enter the Docker image (e.g., nginx:latest, default: docker.io/ruslanmv/hello-react:1.0.0):
Enter the Kubernetes namespace to deploy to (e.g., my-namespace, default: ibmid-667000nwl8-hktijvj4):
[INFO] Using default namespace: ibmid-667000nwl8-hktijvj4
Enter the container port your application listens on (e.g., 80, default: 8080):
Enter the number of replicas (e.g., 1, default: 1):

====== Resource Allocation ======
Enter CPU request for the container (e.g., 1, 500m, default: 1):
Enter CPU limit for the container (e.g., 2, 1000m, default: 2):
Enter Memory request for the container (e.g., 128Mi, default: 128Mi):
Enter Memory limit for the container (e.g., 256Mi, default: 256Mi):
Enter the directory to save YAML files (default: ./hello-react-kube-config):
```

In this example, we've accepted all default values by pressing Enter at each prompt.

**Step 3: Configuration Summary and YAML Generation**

After gathering the information, the script will display a summary of your configuration and ask for confirmation to generate the YAML files.

```text
====== Configuration Summary ======
Application Name: hello-react
Docker Image:     docker.io/ruslanmv/hello-react:1.0.0
Namespace:        ibmid-667000nwl8-hktijvj4
Container Port:   8080
Service Port Name:http-8080 (for Service and Route)
Replicas:         1
CPU Request:      1, CPU Limit: 2
Memory Request:   128Mi, Memory Limit: 256Mi
Output Directory: ./hello-react-kube-config
Common Labels (for Deployment, Service, Route metadata.labels):
  app: hello-react
  app.kubernetes.io/component: hello-react
  app.kubernetes.io/instance: hello-react
  app.kubernetes.io/name: hello-react
  app.kubernetes.io/part-of: hello-react-app
  app.openshift.io/runtime-version: "1.0.0"
Selector Match Labels (for Deployment spec.selector):
    matchLabels:
      app: hello-react
Pod Template Labels (for Deployment spec.template.metadata.labels):
    metadata:
      labels:
        app: hello-react
        deployment: hello-react

The script will generate YAML files for Deployment, Service, and potentially Route (OpenShift).
Do you want to proceed with generating these YAML files in './hello-react-kube-config'? (yes/no): yes
```

Upon confirming 'yes', the script creates the specified output directory and generates the YAML files:

```text
[SUCCESS] Output directory './hello-react-kube-config' ensured.
[SUCCESS] Generated ./hello-react-kube-config/hello-react-deployment.yaml
[SUCCESS] Generated ./hello-react-kube-config/hello-react-service.yaml
[SUCCESS] Generated ./hello-react-kube-config/hello-react-route.yaml (OpenShift Route)
```
*(As mentioned, we won't show the content of these YAML files here, assuming they are detailed elsewhere in your blog.)*

**Step 4: Deployment Confirmation and Process**

Next, the script will ask if you want to deploy these generated files to your OpenShift cluster.

```text
[INFO] YAML files have been generated in './hello-react-kube-config'.
Do you want to deploy these generated files to namespace 'ibmid-667000nwl8-hktijvj4' now? (yes/no): yes
```

If you confirm, it will proceed with the deployment, applying each configuration:

```text
====== Deployment Process ======
[INFO] Namespace 'ibmid-667000nwl8-hktijvj4' already exists.

[INFO] Applying Deployment (./hello-react-kube-config/hello-react-deployment.yaml)...
deployment.apps/hello-react configured
[SUCCESS] Deployment applied/configured.

[INFO] Applying Service (./hello-react-kube-config/hello-react-service.yaml)...
service/hello-react configured
[SUCCESS] Service applied/configured.

[INFO] Applying Route (./hello-react-kube-config/hello-react-route.yaml)...
route.route.openshift.io/hello-react configured
[SUCCESS] Route applied/configured.
```

**Step 5: Deployment Succeeded!**

Finally, you'll get a success message and some helpful commands to check on your newly deployed application.

```text
[SUCCESS] All selected configurations applied!

[INFO] You can check the status of your deployment with the following commands:
  kubectl get deployments -n ibmid-667000nwl8-hktijvj4
  kubectl get pods -n ibmid-667000nwl8-hktijvj4 -w
  kubectl get services -n ibmid-667000nwl8-hktijvj4
  kubectl get routes -n ibmid-667000nwl8-hktijvj4
  Access your application (once ready) via: http://your-application-route-url or https://your-application-route-url
  kubectl logs -f deployment/hello-react -n ibmid-667000nwl8-hktijvj4
  Use './check_kubectl.sh' (if available) for a detailed status check.

[INFO] It might take a few moments for the pods to be ready and the route (if applicable) to be active.
==============================================================
```

Your application is now being deployed! The script also helpfully suggests using `./check_kubectl.sh` for a more detailed status, which we'll cover shortly.

### Part 2: Direct Deployment with `deploy_kubectl.sh` (Alternative)

You might have another script, `deploy_kubectl.sh`, which focuses on directly deploying your application. This script also interactively gathers information but might use different defaults or proceed straight to deployment without the explicit step of saving YAML files to a directory first.

**Running the `deploy_kubectl.sh` script:**

```bash
bash deploy_kubectl.sh
```

**Example Interaction and Deployment:**

This script will also prompt for application details. Notice in the example output below, the default CPU and Memory requests/limits might differ from the previous script.

```text
[INFO] kubectl found.
=====================================================
 Kubernetes/OpenShift Interactive Deployment Script
=====================================================

Enter the application name (e.g., my-react-app): hello-react
Enter the Docker image (e.g., docker.io/ruslanmv/hello-react:1.0.0): docker.io/ruslanmv/hello-react:1.0.0
Enter the Kubernetes namespace to deploy to (e.g., my-namespace): ibmid-667000nwl8-hktijvj4
[INFO] Using current kubectl context namespace: ibmid-667000nwl8-hktijvj4
Enter the container port your application listens on (e.g., 8080): 8080
Enter the number of replicas (e.g., 1): 1
Enter CPU request for the container (e.g., 100m for 0.1 CPU, default: 250m):
Enter CPU limit for the container (e.g., 500m for 0.5 CPU, default: 500m):
Enter Memory request for the container (e.g., 128Mi, default: 128Mi):
Enter Memory limit for the container (e.g., 256Mi, default: 256Mi):

-------------------- Deployment Summary --------------------
Application Name: hello-react
Docker Image:     docker.io/ruslanmv/hello-react:1.0.0
Namespace:        ibmid-667000nwl8-hktijvj4
Container Port:   8080
Service Port Name:http-8080 (exposing container port 8080)
Replicas:         1
CPU Request:      250m
CPU Limit:        500m
Memory Request:   128Mi
Memory Limit:     256Mi
----------------------------------------------------------

The following Kubernetes/OpenShift resources will be configured:
1. Deployment: Manages the application pods.
2. Service: Exposes the application internally within the cluster.
3. Route (OpenShift specific): Exposes the application externally via a URL.
[WARN] The 'Route' resource is specific to OpenShift. If you are on a standard Kubernetes cluster, you might need an 'Ingress' resource instead, which requires an Ingress controller to be set up.

Do you want to proceed with the deployment? (yes/no): yes
[INFO] Applying Deployment...
deployment.apps/hello-react created
[SUCCESS] Deployment applied/configured.

[INFO] Applying Service...
service/hello-react created
[SUCCESS] Service applied/configured.

[INFO] Applying Route (OpenShift specific)...
route.route.openshift.io/hello-react created
[SUCCESS] Route applied/configured.

[SUCCESS] All configurations applied!

[INFO] You can check the status of your deployment with the following commands:
  kubectl get deployments -n ibmid-667000nwl8-hktijvj4
  kubectl get pods -n ibmid-667000nwl8-hktijvj4 -w (add -w to watch)
  kubectl get services -n ibmid-667000nwl8-hktijvj4
  kubectl get routes -n ibmid-667000nwl8-hktijvj4 (for OpenShift, to find the URL)
  kubectl logs -f deployment/hello-react -n ibmid-667000nwl8-hktijvj4 (to see application logs)

[INFO] It might take a few moments for the pods to be ready and the route to be active.
=====================================================
```
This provides another streamlined way to get your application running quickly.

### Part 3: Verifying Your Deployment with `check_kubectl.sh`

Once your application is deployed (using either of the methods above), you'll want to check its status in detail. The `check_kubectl.sh` script is perfect for this.

**Step 1: Run the Checker Script**

Execute the script like so:

```bash
bash check_kubectl.sh
```

**Step 2: Provide Application Details**

The script will ask for the application name and the namespace where it's deployed.

```text
[INFO] kubectl found.
==========================================================
 Kubernetes/OpenShift Interactive Deployment Checker Script
==========================================================

Enter the application name of the deployment to check (e.g., hello-react): hello-react
Enter the Kubernetes namespace where the application is deployed: ibmid-667000nwl8-hktijvj4
[INFO] Checking deployment for application 'hello-react' in namespace 'ibmid-667000nwl8-hktijvj4'...
```

**Step 3: Review the Detailed Output**

The script then queries `kubectl` for comprehensive information about your Deployment, associated Pods, Service, and the OpenShift Route. The output is quite verbose but gives you a clear picture of your application's state.

Below is a snippet of what you might see (the actual output is much longer and very detailed):

```text
==================== Deployment: hello-react ====================
[INFO] Getting Deployment details...
NAME          READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS    IMAGES                                   SELECTOR
hello-react   1/1     1            1           3m20s   hello-react   docker.io/ruslanmv/hello-react:1.0.0   app=hello-react

Describing Deployment 'hello-react':
Name:                           hello-react
Namespace:                      ibmid-667000nwl8-hktijvj4
CreationTimestamp:              Sun, 11 May 2025 11:21:29 +0200
Labels:                         app=hello-react
                                app.kubernetes.io/component=frontend
                                app.kubernetes.io/instance=hello-react
                                app.kubernetes.io/name=hello-react
                                app.kubernetes.io/part-of=hello-react-app
                                app.kubernetes.io/version=1.0.0
Annotations:                    deployment.kubernetes.io/revision: 1
Selector:                       app=hello-react
Replicas:                       1 desired | 1 updated | 1 total | 1 available | 0 unavailable
...
Pod Template:
  Labels:  app=hello-react
           app.kubernetes.io/component=frontend
...
  Containers:
   hello-react:
    Image:        docker.io/ruslanmv/hello-react:1.0.0
    Port:         8080/TCP
...
    Limits:
      cpu:        500m
      memory:     256Mi
    Requests:
      cpu:        250m
      memory:     128Mi
...
Events:
  Type    Reason             Age     From                   Message
  ----    ------             ----    ----                   -------
  Normal  ScalingReplicaSet  3m19s   deployment-controller  Scaled up replica set hello-react-779d45fcc to 1

==================== Pods for Deployment: hello-react ====================
[INFO] Getting Pods associated with Deployment 'hello-react' (using label app=hello-react)...
NAME                            READY   STATUS    RESTARTS   AGE     IP            NODE         NOMINATED NODE   READINESS GATES
hello-react-779d45fcc-9vk6t   1/1     Running   0          3m20s   172.17.3.60   10.240.64.4  <none>           <none>

==================== Pod Details: hello-react-779d45fcc-9vk6t ====================
Describing Pod 'hello-react-779d45fcc-9vk6t':
Name:                   hello-react-779d45fcc-9vk6t
...
Status:                 Running
IP:                     172.17.3.60
...
Events:
  Type    Reason          Age     From               Message
  ----    ------          ----    ----               -------
  Normal  Scheduled       3m21s   default-scheduler  Successfully assigned ibmid-667000nwl8-hktijvj4/hello-react-779d45fcc-9vk6t to 10.240.64.4
  Normal  AddedInterface  3m22s   multus             Add eth0 [172.17.3.60/32] from k8s-pod-network
  Normal  Pulled          3m21s   kubelet            Container image "docker.io/ruslanmv/hello-react:1.0.0" already present on machine
  Normal  Created         3m21s   kubelet            Created container hello-react
  Normal  Started         3m21s   kubelet            Started container hello-react

Recent logs for Pod 'hello-react-779d45fcc-9vk6t' (last 50 lines):
...
Do you want to view full (streaming) logs for pod hello-react-779d45fcc-9vk6t? (yes/no, default: no) no

==================== Service: hello-react ====================
[INFO] Getting Service details...
NAME          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE     SELECTOR
hello-react   ClusterIP   172.21.167.176   <none>        8080/TCP   3m33s   app=hello-react
...
Endpoints:         172.17.3.60:8080
...

==================== Endpoints for Service: hello-react ====================
[INFO] Getting Endpoints for Service 'hello-react'...
NAME          ENDPOINTS          AGE
hello-react   172.17.3.60:8080   3m35s

==================== Route: hello-react (OpenShift Specific) ====================
[INFO] Getting Route details...
NAME          HOST/PORT                                                                                                       PATH      SERVICES      PORT        TERMINATION     WILDCARD
hello-react   hello-react-ibmid-667000nwl8-hktijvj4.roks-demo2v-13d45cd84769aede38d625cd31842ee0-0000.us-south.containers.appdomain.cloud             hello-react   http-8080   edge/Redirect   None
...
Spec:
  Host: hello-react-ibmid-667000nwl8-hktijvj4.roks-demo2v-13d45cd84769aede38d625cd31842ee0-0000.us-south.containers.appdomain.cloud
...
Status:
  Ingress:
  - Conditions:
    ...
    Host:           hello-react-ibmid-667000nwl8-hktijvj4.roks-demo2v-13d45cd84769aede38d625cd31842ee0-0000.us-south.containers.appdomain.cloud
...

==================== Check Complete ====================
```
*(Note: You might notice a `success: command not found` message near the end of the Route details in the example output. This is a minor issue within that particular `check_kubectl.sh` script and doesn't affect its ability to display the status information from OpenShift.)*

This checker script is invaluable for troubleshooting or simply understanding all the components of your running application. Pay close attention to the `READY` status for Deployments and Pods, and the `HOST/PORT` for the Route to access your application.



## 9. Improvements & Enhancements

Now that your `hello-react` application is up and running on OpenShift, let's explore several ways you can enhance its robustness, configurability, and manageability. These improvements are common best practices for production-grade deployments.

* **Externalize Configuration:**
    Instead of baking configuration directly into your application image, use OpenShift `ConfigMap`s for environment-specific settings (like API URLs, feature flags, etc.). You can mount these `ConfigMap`s as environment variables or as files into your Pods.
    For React applications (built with tools like Vite or Create React App), environment variables (e.g., prefixed with `VITE_` for Vite or `REACT_APP_` for Create React App) can be:
    * Set at build time if the values are known then.
    * Injected at runtime: A common pattern for applications served by Nginx is to have a small entrypoint script in the Nginx container. This script can read environment variables (populated from `ConfigMap`s or `Secret`s) and generate a `config.js` file (e.g., `/usr/share/nginx/html/config.js`) when the container starts. Your `index.html` would then include `<script src="/config.js"></script>` to load this runtime configuration.

* **Secure Secrets:**
    For sensitive data such as API keys, database passwords, or private certificates, always use OpenShift `Secret`s. Like `ConfigMap`s, `Secret`s can be mounted securely into your Pods as environment variables or files. **Never hardcode secrets in your Docker image or version control.**

* **Health-Checking (Probes):**
    OpenShift (and Kubernetes) uses probes to monitor the health of your application's containers.
    * **Liveness Probes:** Determine if a container is running correctly. If a liveness probe fails repeatedly, OpenShift will restart the container.
    * **Readiness Probes:** Determine if a container is ready to accept traffic. A Pod is only considered ready (and thus eligible to receive traffic from a Service) when all of its containers are ready. If a readiness probe fails, the Pod's IP address is removed from the Service's endpoints until it becomes ready again.

    You should add `livenessProbe` and `readinessProbe` sections to your `Deployment`'s container specification. For the `hello-react` app (assuming it's served by Nginx or a similar web server on port 8080 as configured by our script), an HTTP GET probe is usually sufficient:

    ```yaml
    # Excerpt from your Deployment YAML (e.g., hello-react-deployment.yaml)
    # spec:
    #   template:
    #     spec:
    #       containers:
    #       - name: hello-react
    #         image: docker.io/ruslanmv/hello-react:1.0.0
    #         ports:
    #         - containerPort: 8080 # Your application's listening port
    #           protocol: TCP
    #         livenessProbe:
    #           httpGet:
    #             path: /index.html # Or simply / if your server handles it
    #             port: 8080
    #           initialDelaySeconds: 15 # Time to wait before the first probe
    #           periodSeconds: 20     # How often to perform the probe
    #           timeoutSeconds: 5       # When the probe times out
    #           failureThreshold: 3   # Restart after 3 consecutive failures
    #         readinessProbe:
    #           httpGet:
    #             path: /index.html # Or simply /
    #             port: 8080
    #           initialDelaySeconds: 5 # Time to wait before the first probe
    #           periodSeconds: 10    # How often to perform the probe
    #           timeoutSeconds: 5      # When the probe times out
    #           failureThreshold: 3  # Mark as not ready after 3 consecutive failures
    #           successThreshold: 1  # Mark as ready after 1 successful probe
    ```
    Adjust `path`, `port`, `initialDelaySeconds`, `periodSeconds`, etc., based on your application's specific startup time and behavior.

* **Auto-scaling:**
    To handle varying loads, you can configure a `HorizontalPodAutoscaler` (HPA). This will automatically increase or decrease the number of Pods for your `Deployment` based on metrics like CPU utilization or custom metrics.

    Here's an example `hpa.yaml` for the `hello-react` application:
    ```yaml
    # hpa.yaml
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: hello-react
      # namespace: ibmid-667000nwl8-hktijvj4 # Specify if not deploying to the current/default namespace
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: hello-react # This must match the name of your Deployment
      minReplicas: 1
      maxReplicas: 5 # Adjust max replicas as needed
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            # Target 80% CPU utilization across all pods for this deployment
            # The HPA will add pods if average utilization exceeds this,
            # and remove pods if it falls significantly below.
            averageUtilization: 80
    ```
    Apply this configuration using:
    ```bash
    kubectl apply -f hpa.yaml -n ibmid-667000nwl8-hktijvj4 # Use your specific namespace
    ```

* **CI/CD Pipeline:**
    Automate your build, test, and deployment processes by setting up a CI/CD pipeline. OpenShift offers **OpenShift Pipelines** (based on Tekton) for building pipelines natively within the cluster. Alternatively, you can integrate with external CI/CD tools like GitHub Actions, Jenkins, GitLab CI, Azure DevOps, etc., to trigger deployments to OpenShift whenever you push changes to your Git repository.

* **Monitoring & Logging:**
    Effective monitoring and logging are crucial for maintaining application health and troubleshooting issues.
    * **Monitoring:** OpenShift typically includes a built-in monitoring stack (often Prometheus for metrics collection and Grafana for visualization). Explore the "Observe" section in the OpenShift web console to view metrics for your projects, pods, and nodes.
    * **Logging:** Ensure your application logs its output to `stdout` (standard output) and `stderr` (standard error). OpenShift automatically collects these logs. You can view them using the `kubectl logs <pod-name> -n <your-namespace>` command, or through the OpenShift web console by navigating to your pod and viewing its logs.

    ![](assets/2025-05-10-19-57-40.png)
    *(Caption suggestion: The OpenShift web console provides integrated views for monitoring metrics and accessing application logs.)*

Congratulations! You’ve now explored various enhancements that can take your simple React application deployment on OpenShift (or ROKS - Red Hat OpenShift on IBM Cloud) to a more robust, production-ready state. Implementing these practices will improve your application's reliability, scalability, and maintainability.


Using interactive scripts like these can significantly simplify and accelerate your deployment workflow on OpenShift. They promote consistency, reduce manual errors, and provide a guided experience that's especially helpful when you're starting out or need to perform deployments regularly. By automating YAML generation and application deployment, you can focus more on developing your applications and less on the intricacies of manual configuration.
