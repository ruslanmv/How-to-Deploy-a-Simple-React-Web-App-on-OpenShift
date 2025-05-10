#!/usr/bin/env bash

# Script to interactively set up Docker Hub context, then build and push a Docker image
# to Docker Hub.

# --- Configuration (can be overridden by user input) ---
DEFAULT_IMAGE_NAME="hello-react"
DEFAULT_IMAGE_TAG="1.0.0"
DOCKERHUB_USERNAME="" # Will be prompted

# --- Global Variables (will be set during script execution) ---
IMAGE_NAME=""
IMAGE_TAG=""
FULL_IMAGE_PATH=""

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

# Function for Docker Hub Login
login_to_dockerhub() {
    echo ""
    echo "➡️ Logging into Docker Hub..."

    # Check if already logged in to Docker Hub by inspecting docker's config.json
    # This is a basic check; 'docker login' will ultimately handle re-auth if needed.
    local docker_config_path="${HOME}/.docker/config.json"
    local logged_in_user=""

    if [ -f "$docker_config_path" ]; then
        # Attempt to find if we're logged into docker.io (Docker Hub)
        # This grep is a heuristic and might not be foolproof for all config.json structures
        if grep -q "\"https://index.docker.io/v1/\"" "$docker_config_path"; then
             # Try to extract username if possible (this is more complex and varies)
             # For simplicity, we'll just inform the user they might be logged in.
            echo "ℹ️ You may already be logged into Docker Hub."
            read -r -p "Do you want to re-login or use the current Docker Hub session? (Type 'relogin' or press Enter for current): " relogin_choice
            if [[ ! "$relogin_choice" =~ ^relogin$ ]]; then
                # Attempt to get the username for the current Docker Hub login if possible
                # This is tricky as 'docker system info' doesn't reliably show it.
                # 'docker info' might, or by parsing config.json, but it's complex.
                # We'll rely on the user providing it or it being entered for the push.
                echo "✅ Assuming current Docker Hub session is valid. You'll still need to provide your username for tagging."
                return 0 # Skip explicit login command
            fi
        fi
    fi

    # Prompt for Docker Hub username if not already set
    if [ -z "$DOCKERHUB_USERNAME" ]; then
        read -r -p "Enter your Docker Hub Username: " DOCKERHUB_USERNAME_INPUT
        if [ -z "$DOCKERHUB_USERNAME_INPUT" ]; then
            echo "❌ Docker Hub Username cannot be empty."
            exit 1
        fi
        DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME_INPUT"
    else
        echo "ℹ️ Using Docker Hub Username: $DOCKERHUB_USERNAME (from previous input or environment)"
    fi


    echo "Attempting login for user '$DOCKERHUB_USERNAME'. You will be prompted for your Docker Hub password or access token."
    if ! docker login -u "$DOCKERHUB_USERNAME"; then
        echo "❌ Docker Hub login failed. Please check your username and password/token."
        exit 1
    fi
    echo "✅ Successfully logged into Docker Hub as $DOCKERHUB_USERNAME."
}

# Function to get image details
get_image_details() {
    echo ""
    echo "➡️ Defining Image Details..."
    read -r -p "Enter the image name [default: $DEFAULT_IMAGE_NAME]: " IMAGE_NAME_INPUT
    IMAGE_NAME=${IMAGE_NAME_INPUT:-$DEFAULT_IMAGE_NAME}

    read -r -p "Enter the image tag [default: $DEFAULT_IMAGE_TAG]: " IMAGE_TAG_INPUT
    IMAGE_TAG=${IMAGE_TAG_INPUT:-$DEFAULT_IMAGE_TAG}

    # Prompt for Docker Hub username if not already set by login_to_dockerhub
    if [ -z "$DOCKERHUB_USERNAME" ]; then
        read -r -p "Enter your Docker Hub Username (this will be part of the image path): " DOCKERHUB_USERNAME_INPUT
        if [ -z "$DOCKERHUB_USERNAME_INPUT" ]; then
            echo "❌ Docker Hub Username cannot be empty for tagging."
            exit 1
        fi
        DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME_INPUT"
    fi

    # Docker Hub image path format: <username>/<repository>:<tag>
    # The 'docker.io/' prefix is optional and usually omitted for Docker Hub.
    FULL_IMAGE_PATH="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo "✅ Image will be tagged as: $FULL_IMAGE_PATH"
}


# --- Main Script Logic ---
main() {
    echo "🚀 Docker Build and Push to Docker Hub Script 🚀"

    # --- Prerequisite Checks ---
    ensure_command "docker" "Please install Docker Desktop or Docker Engine."
    check_docker_daemon

    # --- Docker Hub Setup ---
    get_image_details # This will set DOCKERHUB_USERNAME, IMAGE_NAME, IMAGE_TAG, FULL_IMAGE_PATH
    login_to_dockerhub # This will use/confirm DOCKERHUB_USERNAME

    # --- Dockerfile Check ---
    echo ""
    echo "➡️ Checking for Dockerfile..."
    if [ ! -f Dockerfile ]; then
        echo "❌ Error: Dockerfile not found in the current directory (PWD: $(pwd))."
        echo "   This script must be run from the root of your project where the Dockerfile exists."
        exit 1
    fi
    echo "✅ Dockerfile found."

    # --- Display Configuration & Final Confirmation ---
    echo ""
    echo "---------------------------------------------------------------------"
    echo "SUMMARY OF ACTIONS TO BE PERFORMED:"
    echo "   Docker Hub Username:    $DOCKERHUB_USERNAME"
    echo "   Image to Build & Push:  $IMAGE_NAME"
    echo "   Tag for Image:          $IMAGE_TAG"
    echo "   Full Image Path:        $FULL_IMAGE_PATH"
    echo "   Dockerfile Directory:   $(pwd)"
    echo "---------------------------------------------------------------------"
    read -r -p "Proceed with Docker build and image push to Docker Hub? (y/N): " final_confirmation
    if [[ ! "$final_confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi

    # Enable 'exit on error' for the critical Docker operations
    set -e

    # 1. Build and Tag the Image for Docker Hub
    echo ""
    echo "➡️ Building Docker image: $FULL_IMAGE_PATH ..."
    docker build -t "$FULL_IMAGE_PATH" . # set -e will handle exit on failure

    echo "✅ Docker image built and tagged successfully as $FULL_IMAGE_PATH."

    # 2. Docker login was already handled by login_to_dockerhub()

    # 3. Push the Image to Docker Hub
    echo ""
    echo "➡️ Pushing image to $FULL_IMAGE_PATH ..."
    docker push "$FULL_IMAGE_PATH" # set -e will handle exit on failure
    echo "✅ Docker image pushed successfully to $FULL_IMAGE_PATH."

    # 4. Verify Image (by suggesting manual check)
    echo ""
    echo "➡️ Verification:"
    echo "   You can verify the image on Docker Hub by visiting:"
    echo "   https://hub.docker.com/r/${DOCKERHUB_USERNAME}/${IMAGE_NAME}/tags"
    echo "   It might take a moment for the new tag to appear."
    set +e # Disable exit on error as we are done with critical operations

    echo ""
    echo "🎉 All operations completed successfully! 🎉"
    echo "Your image should now be available at: $FULL_IMAGE_PATH"
}

# --- Script Execution ---
# Call the main function.
main