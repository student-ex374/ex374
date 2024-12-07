#!/bin/bash

REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
GITLAB_URL="https://git.lab.example.com"
TOKEN="auto-clone-token-123"  # Replace with your GitLab Personal Access Token
WORKSTATION_DIR="/home/student/projects"  # Directory to clone the repository
GITHUB_REPO_URL="https://github.com/sugum2901/web_server.git"

# Helper function to execute commands with error handling
execute() {
  echo "Running: $*"
  "$@"
  if [[ $? -ne 0 ]]; then
    echo "Error executing: $*"
    exit 1
  fi
}

# Function to validate the Personal Access Token
validate_token() {
  echo "Validating Personal Access Token (PAT)..."
  response=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/user")
  if echo "$response" | grep -q '"username"'; then
    echo "PAT validation successful."
  else
    echo "Error: Invalid or insufficiently scoped PAT. Please ensure it has 'api' and 'write_repository' scopes."
    exit 1
  fi
}

# Function to delete the repository if it exists
delete_repository() {
  echo "Checking if repository '$REPO_NAME' exists..."
  project_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | grep -oP '"id":\d+' | head -1 | grep -oP '\d+')
  if [[ -n $project_id ]]; then
    echo "Repository exists. Deleting it..."
    curl -s --request DELETE --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$project_id"
    echo "Repository deleted."
  else
    echo "Repository does not exist. Skipping deletion."
  fi
}

# Function to create a new repository
create_repository() {
  echo "Creating repository '$REPO_NAME'..."
  namespace_id=$(curl -s --header "PRIVATE-TOKEN: $
