#!/usr/bin/env bash

# Script to interactively set up IBM Cloud context, then build and push a Docker image
# to IBM Cloud Container Registry (ICR)

# --- Configuration (can be overridden by script logic or user input) ---
IMAGE_NAME="hello-react"
IMAGE_TAG="1.0.0" # Matches the blog post example

# --- Global Variables (will be set during script execution) ---
ICR_HOSTNAME=""
ICR_NAMESPACE=""
FULL_IMAGE_PATH=""
# TARGET_RESOURCE_GROUP_NAME="" # We'll just let 'ibmcloud target -g' set it for the session

# --- Helper Functions ---
# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if Docker daemon is running
check_docker_daemon() {
    echo "➡️ Checking if Docker daemon is running..."
    if ! docker info &>/dev/null; then
        echo "❌ Error: Docker daemon does not appear to be running."
        echo "Please start Docker and try again."
        exit 1
    fi
    echo "✅ Docker daemon is running."
}

# Function to ensure a command is installed, guides user if not
ensure_command() {
    local cmd="$1"
    local install_hint="$2"
    if ! command_exists "$cmd"; then
        echo "❌ Error: Required command '$cmd' not found."
        if [ -n "$install_hint" ]; then
            echo "   Hint: $install_hint"
        fi
        exit 1
    fi
    echo "✅ Command '$cmd' is available."
}

# Function for IBM Cloud Login
login_to_ibmcloud() {
    echo ""
    echo "➡️ Logging into IBM Cloud..."
    # Check if already logged in by seeing if 'ibmcloud target' gives a valid output (not an error)
    if ibmcloud target &>/dev/null; then
        echo "ℹ️ You appear to be already logged into IBM Cloud."
        current_account=$(ibmcloud target --output JSON 2>/dev/null | grep '"name":' | head -n 1 | awk -F'"' '{print $4}')
        if [ -z "$current_account" ]; then # Fallback parsing if JSON output failed or different
             current_account=$(ibmcloud target 2>/dev/null | grep Account: | awk '{print $2}')
        fi

        if [ -n "$current_account" ]; then
            echo "   Current Account: $current_account"
        fi
        read -r -p "Do you want to re-login or use the current session? (Type 'relogin' or press Enter for current): " relogin_choice
        if [[ ! "$relogin_choice" =~ ^relogin$ ]]; then
            echo "✅ Using current IBM Cloud session."
            return 0
        fi
    fi

    read -r -p "Do you want to use SSO (Single Sign-On) for IBM Cloud login? (y/N): " use_sso
    local login_cmd_base="ibmcloud login"
    local login_options="-a https://cloud.ibm.com" # Default endpoint

    if [[ "$use_sso" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        login_options="--sso"
        echo "Please follow the prompts in your web browser to complete SSO login."
    else
        echo "You will be prompted for your IBM Cloud credentials or API key."
    fi

    if ! $login_cmd_base $login_options; then
        echo "❌ IBM Cloud login failed. Please check your credentials and connection."
        exit 1
    fi
    echo "✅ Successfully logged into IBM Cloud."
    echo "Current target information:"
    ibmcloud target
}

# Function to select target resource group
select_target_resource_group() {
    echo ""
    echo "➡️ Managing Target Resource Group..."
    echo "Current target:"
    # Display current resource group from 'ibmcloud target'
    ibmcloud target | grep "Resource group:" || echo "   Resource group: Not specifically targeted (using default for account/region)"
    echo ""
    echo "Listing available resource groups (this may take a moment)..."
    # Use default output for 'ibmcloud resource groups'
    if ! ibmcloud resource groups; then
        echo "⚠️ Could not list resource groups. You may need to specify one manually if namespace creation depends on it."
        # Don't exit, but warn. The user can still try to type a name/ID.
    fi
    echo ""
    read -r -p "Enter the NAME or ID of the resource group to target (or press Enter to keep current/default): " rg_name_or_id

    if [ -n "$rg_name_or_id" ]; then
        echo "Setting target resource group to '$rg_name_or_id'..."
        if ! ibmcloud target -g "$rg_name_or_id"; then
            echo "⚠️ Failed to target resource group '$rg_name_or_id'. Please check the name/ID."
            echo "   Continuing with previous/default target. This might affect namespace creation if a specific group is required."
        else
            echo "✅ Successfully targeted resource group '$rg_name_or_id'."
        fi
    else
        echo "ℹ️ Keeping current/default resource group target."
    fi
    echo "Updated target information:"
    ibmcloud target
}


# Function to ensure Container Registry plugin is installed/updated
ensure_cr_plugin() {
    echo ""
    echo "➡️ Checking IBM Cloud Container Registry plugin..."
    if ! ibmcloud plugin show container-registry &>/dev/null; then
        echo "Container Registry plugin not found. Installing..."
        # Using 'ibmcloud plugin install container-registry' without -r as per user feedback
        if ! ibmcloud plugin install container-registry; then
            echo "❌ Failed to install Container Registry plugin."
            exit 1
        fi
        echo "✅ Container Registry plugin installed successfully."
        echo "A brief pause for plugin to initialize..."
        sleep 3 # Give a few seconds for CLI to recognize the new plugin fully
    else
        echo "✅ Container Registry plugin is already installed."
        read -r -p "Do you want to check for updates to the Container Registry plugin? (y/N): " update_plugin
        if [[ "$update_plugin" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            echo "Checking for plugin updates..."
            # Using 'ibmcloud plugin update container-registry' without -r
            ibmcloud plugin update container-registry || echo "ℹ️ Plugin update check finished. Review output if any issues."
            echo "✅ Plugin update check complete."
        fi
    fi
}

# Function to select and set ICR Region, and determine ICR_HOSTNAME
select_icr_region_and_hostname() {
    echo ""
    echo "➡️ Managing IBM Cloud Container Registry Region..."

    # Static map of common region keys to their ICR hostnames
    # This is used because 'ibmcloud cr regions' command is reported as unavailable
    declare -A REGION_TO_HOSTNAME_MAP
    REGION_TO_HOSTNAME_MAP=(
        ["us-south"]="us.icr.io"
        ["us-east"]="us-east.icr.io"
        ["eu-de"]="de.icr.io"
        ["eu-gb"]="uk.icr.io"  # uk-south often uses eu-gb key
        ["uk-south"]="uk.icr.io" # Alias for clarity
        ["jp-tok"]="jp.icr.io"
        ["jp-osa"]="jp2.icr.io"
        ["au-syd"]="au.icr.io"
        ["ca-tor"]="ca.icr.io"
        ["br-sao"]="br.icr.io"
        ["kr-seo"]="kr.icr.io"
        ["eu-central"]="eu.icr.io" # Often an alias for eu-de or a broader regional endpoint
        ["global"]="icr.io"
    )

    local current_set_region_key=""
    local current_set_hostname=""

    # Attempt to get current region and registry hostname
    current_region_info=$(ibmcloud cr region 2>/dev/null)
    if [ -n "$current_region_info" ] && [[ "$current_region_info" == *"the registry is"* ]]; then
        echo "$current_region_info"
        current_set_region_key=$(echo "$current_region_info" | awk -F"'" '{print $2}')
        current_set_hostname=$(echo "$current_region_info" | awk -F"'" '{print $4}')
        # Validate if the parsed hostname matches our map for the parsed key
        if [ -n "${REGION_TO_HOSTNAME_MAP[$current_set_region_key]}" ] && \
           [ "${REGION_TO_HOSTNAME_MAP[$current_set_region_key]}" != "$current_set_hostname" ]; then
            echo "⚠️ Warning: Auto-detected hostname '$current_set_hostname' for region '$current_set_region_key' differs from internal map ('${REGION_TO_HOSTNAME_MAP[$current_set_region_key]}'). Using auto-detected."
        fi
        ICR_HOSTNAME="$current_set_hostname" # Prefer auto-detected if successful
    else
        echo "Could not determine current ICR region details automatically. Please select one."
    fi
    echo ""
    echo "Please select your target ICR Region Key from the list below or IBM Cloud documentation."
    echo "Common Region Keys and their Hostnames:"
    echo "  us-south -> us.icr.io"
    echo "  us-east  -> us-east.icr.io"
    echo "  eu-de    -> de.icr.io"
    echo "  eu-gb    -> uk.icr.io (for UK South)"
    echo "  jp-tok   -> jp.icr.io"
    echo "  au-syd   -> au.icr.io"
    echo "  ca-tor   -> ca.icr.io"
    echo "  global   -> icr.io (Global multi-region domain)"
    echo "  (Refer to IBM Cloud docs for a complete, up-to-date list if your region is not shown)"
    echo ""

    local prompt_message="Enter the target ICR Region Key (e.g., us-south)"
    if [ -n "$current_set_region_key" ]; then
        prompt_message="$prompt_message or press Enter to use current ('$current_set_region_key')"
    fi
    prompt_message="$prompt_message: "
    read -r -p "$prompt_message" new_region_key_input

    local final_region_key_to_set="$current_set_region_key" # Default to current if no input
    local region_changed=false

    if [ -n "$new_region_key_input" ]; then
        if [ "$new_region_key_input" != "$current_set_region_key" ]; then
            final_region_key_to_set="$new_region_key_input"
            region_changed=true
        else
            echo "ℹ️ Region '$new_region_key_input' is already the current target."
        fi
    elif [ -z "$current_set_region_key" ]; then # No input and no current region known
        echo "❌ No region selected or previously set. Please enter a valid region key."
        exit 1
    fi

    if [ "$region_changed" = true ]; then
        echo "Setting ICR region to '$final_region_key_to_set'..."
        if ! ibmcloud cr region-set "$final_region_key_to_set"; then
            echo "❌ Failed to set ICR region to '$final_region_key_to_set'. Please check the key and try again."
            exit 1
        fi
        echo "✅ ICR region set to '$final_region_key_to_set'."
        # After setting, try to get the hostname from our map
        if [ -n "${REGION_TO_HOSTNAME_MAP[$final_region_key_to_set]}" ]; then
            ICR_HOSTNAME="${REGION_TO_HOSTNAME_MAP[$final_region_key_to_set]}"
        else
            echo "⚠️ Hostname for region key '$final_region_key_to_set' not found in internal map."
            read -r -p "Please manually enter the Registry domain name for '$final_region_key_to_set' (e.g., us.icr.io): " ICR_HOSTNAME
        fi
    elif [ -z "$ICR_HOSTNAME" ] && [ -n "$final_region_key_to_set" ]; then # Current region kept, but hostname wasn't pre-filled
        if [ -n "${REGION_TO_HOSTNAME_MAP[$final_region_key_to_set]}" ]; then
            ICR_HOSTNAME="${REGION_TO_HOSTNAME_MAP[$final_region_key_to_set]}"
        else
            echo "⚠️ Hostname for current region key '$final_region_key_to_set' not found in internal map."
            read -r -p "Please manually enter the Registry domain name for '$final_region_key_to_set' (e.g., us.icr.io): " ICR_HOSTNAME
        fi
    elif [ -n "$ICR_HOSTNAME" ]; then
         echo "ℹ️ Using previously determined/current ICR region '$final_region_key_to_set' and hostname '$ICR_HOSTNAME'."
    fi


    if [ -z "$ICR_HOSTNAME" ]; then
        echo "❌ ICR Hostname could not be determined or was not provided for region '$final_region_key_to_set'."
        exit 1
    fi
    echo "✅ Using ICR Region Key: '$final_region_key_to_set', Hostname: '$ICR_HOSTNAME'"
}

# Function to select or create ICR Namespace
select_or_create_icr_namespace() {
    echo ""
    echo "➡️ Managing IBM Cloud Container Registry Namespace..."
    echo "Listing available ICR namespaces (this may take a moment)..."
    # Run in subshell to prevent script exit if command fails (e.g., no namespaces exist)
    (ibmcloud cr namespace-list) || echo "ℹ️ Could not list namespaces or no namespaces exist yet."

    echo ""
    read -r -p "Enter ICR namespace to use/create (e.g., cc-667000nwl8-n8918mfv-cr or my-unique-ns): " selected_ns

    if [ -z "$selected_ns" ]; then
        echo "❌ Namespace cannot be empty."
        exit 1
    fi

    # Check if namespace exists (grep is case-sensitive, -w for whole word, -q for quiet)
    # Running in subshell with || true to handle grep's exit code if no match
    if (ibmcloud cr namespace-list | grep -qw "$selected_ns"); then
        echo "✅ Using existing namespace: $selected_ns"
        ICR_NAMESPACE="$selected_ns"
    else
        echo "Namespace '$selected_ns' not found in the list, or listing failed."
        read -r -p "Do you want to attempt to create namespace '$selected_ns'? (y/N): " create_ns
        if [[ "$create_ns" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            echo "Attempting to create namespace '$selected_ns'..."
            echo "ℹ️ Note: Namespace creation is often tied to the targeted resource group."
            current_rg_info=$(ibmcloud target | grep 'Resource group:')
            if [ -n "$current_rg_info" ]; then echo "   Current target $current_rg_info"; else echo "   Current resource group target is not explicitly set."; fi
            if ! ibmcloud cr namespace-add "$selected_ns"; then
                echo "❌ Failed to create namespace '$selected_ns'."
                echo "   This could be because:"
                echo "     - The name is already taken globally or within your account/region under different rules."
                echo "     - The name has invalid characters."
                echo "     - The currently targeted resource group (see above) is not suitable or you lack permissions."
                echo "   You can try targeting a specific resource group ('ibmcloud target -g YOUR_GROUP') before running this script,"
                echo "   or create the namespace manually via the IBM Cloud console."
                exit 1
            fi
            echo "✅ Namespace '$selected_ns' created successfully."
            ICR_NAMESPACE="$selected_ns"
        else
            echo "❌ Namespace '$selected_ns' was not selected or created. Exiting."
            exit 1
        fi
    fi
}

# --- Main Script Logic ---
main() {
    # Set -e for the main execution block after initial non-critical checks/setups
    # Individual functions will handle their critical exits.

    echo "🚀 Enhanced Docker Build and Push to IBM Cloud Container Registry Script 🚀"

    # --- Prerequisite Checks ---
    ensure_command "docker" "Please install Docker Desktop or Docker Engine."
    ensure_command "ibmcloud" "Please install IBM Cloud CLI. A helper script 'install_ibmcloud_cli.sh' can be used."
    check_docker_daemon

    # --- IBM Cloud Setup ---
    login_to_ibmcloud
    select_target_resource_group
    ensure_cr_plugin
    select_icr_region_and_hostname # Sets ICR_HOSTNAME
    select_or_create_icr_namespace # Sets ICR_NAMESPACE

    # --- Dockerfile Check ---
    echo ""
    echo "➡️ Checking for Dockerfile..."
    if [ ! -f Dockerfile ]; then
        echo "❌ Error: Dockerfile not found in the current directory (PWD: $(pwd))."
        echo "   This script must be run from the root of your project where the Dockerfile exists."
        exit 1
    fi
    echo "✅ Dockerfile found."

    # Construct full image path
    FULL_IMAGE_PATH="${ICR_HOSTNAME}/${ICR_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

    # --- Display Configuration & Final Confirmation ---
    echo ""
    echo "---------------------------------------------------------------------"
    echo "SUMMARY OF ACTIONS TO BE PERFORMED:"
    current_account_name=$(ibmcloud account show --output JSON 2>/dev/null | grep '"name":' | head -n 1 | awk -F'"' '{print $4}')
    if [ -z "$current_account_name" ]; then # Fallback if JSON parse fails
        current_account_name=$(ibmcloud target 2>/dev/null | grep Account: | awk '{for(i=2;i<=NF;i++) printf $i " "; print ""}' | sed 's/ *$//g; s/(.*//g')
    fi
    [ -z "$current_account_name" ] && current_account_name="<Not Available>"
    echo "  Target IBM Cloud Account: $current_account_name"
    current_rg_display=$(ibmcloud target 2>/dev/null | grep 'Resource group:' | sed 's/Resource group:\s*//' || echo "<Default for account/region>")
    echo "  Target Resource Group:  $current_rg_display"
    echo "  Target ICR Hostname:    $ICR_HOSTNAME"
    echo "  Target ICR Namespace:   $ICR_NAMESPACE"
    echo "  Image to Build & Push:  $IMAGE_NAME"
    echo "  Tag for Image:          $IMAGE_TAG"
    echo "  Full Image Path:        $FULL_IMAGE_PATH"
    echo "  Dockerfile Directory:   $(pwd)"
    echo "---------------------------------------------------------------------"
    read -r -p "Proceed with Docker build, ICR Docker login, and image push? (y/N): " final_confirmation
    if [[ ! "$final_confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    # Enable 'exit on error' for the critical Docker and ICR operations
    set -e

    # 1. Build and Tag the Image for ICR
    echo ""
    echo "➡️ Building Docker image: $FULL_IMAGE_PATH ..."
    docker build -t "$FULL_IMAGE_PATH" . # set -e will handle exit on failure

    echo "✅ Docker image built and tagged successfully as $FULL_IMAGE_PATH."

    # 2. Log Local Docker Daemon into IBM Cloud Container Registry
    echo ""
    echo "➡️ Authenticating Docker with IBM Cloud Container Registry ($ICR_HOSTNAME)..."
    # 'ibmcloud cr login' uses the ICR region already set to authenticate Docker
    ibmcloud cr login # set -e will handle exit on failure
    echo "✅ Successfully authenticated Docker with IBM Cloud Container Registry."

    # 3. Push the Image to ICR
    echo ""
    echo "➡️ Pushing image to $FULL_IMAGE_PATH ..."
    docker push "$FULL_IMAGE_PATH" # set -e will handle exit on failure
    echo "✅ Docker image pushed successfully to $FULL_IMAGE_PATH."

    # 4. Verify Image in Private Registry
    echo ""
    echo "➡️ Verifying image in IBM Cloud Container Registry (namespace: $ICR_NAMESPACE)..."
    set +e # Temporarily disable exit on error for the verification grep
    sleep 3 # Brief delay for registry eventual consistency
    if ibmcloud cr image-list --restrict "$ICR_NAMESPACE" | grep -q "$IMAGE_NAME[[:space:]]*$IMAGE_TAG"; then
        echo "✅ Image $IMAGE_NAME:$IMAGE_TAG found in ICR namespace $ICR_NAMESPACE."
    else
        echo "⚠️ Image $IMAGE_NAME:$IMAGE_TAG not immediately confirmed by 'ibmcloud cr image-list'."
        echo "   It might take a moment to appear. You can also check the IBM Cloud console."
        echo "   Full list for namespace $ICR_NAMESPACE (if listing succeeds):"
        ibmcloud cr image-list --restrict "$ICR_NAMESPACE" || echo "   Could not retrieve image list for verification."
    fi
    set -e # Re-enable exit on error

    echo ""
    echo "🎉 All operations completed successfully! 🎉"
    echo "Your image should now be available at: $FULL_IMAGE_PATH"
}

# --- Script Execution ---
# Call the main function.
main