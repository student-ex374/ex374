#!/bin/bash

# Variables
REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
GITLAB_URL="https://git.lab.example.com"
TOKEN="your-secure-token-here"  # Replace with the newly generated PAT
WORKSTATION_DIR="/home/student/projects"  # Directory to clone the repository
GITHUB_REPO_URL="https://github.com/sugum2901/web_server.git"
PROJECT_ID=""

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
  PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | jq -r '.[0].id')
  
  if [[ -n $PROJECT_ID && $PROJECT_ID != "null" ]]; then
    echo "Repository exists with ID $PROJECT_ID. Deleting it..."
    curl -s --request DELETE --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID"
    echo "Delete request sent. Waiting for deletion to complete..."
    sleep 5
  else
    echo "Repository does not exist. Skipping deletion."
  fi
}

# Function to create a new repository
create_repository() {
  echo "Creating repository '$REPO_NAME'..."
  namespace_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/namespaces?search=$USER_USERNAME" | jq -r '.[0].id')

  if [[ -z $namespace_id || $namespace_id == "null" ]]; then
    echo "Error: Could not determine namespace ID for user '$USER_USERNAME'."
    exit 1
  fi

  response=$(curl -s --request POST "$GITLAB_URL/api/v4/projects" \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=$REPO_NAME&namespace_id=$namespace_id&visibility=private")

  echo "Repository creation response: $response"

  PROJECT_ID=$(echo "$response" | jq -r '.id')
  if [[ -n $PROJECT_ID && $PROJECT_ID != "null" ]]; then
    echo "Repository created successfully with ID $PROJECT_ID."
  else
    echo "Error creating repository. Response: $response"
    exit 1
  fi
}

# Function to configure branch protection
configure_branch_protection() {
  echo "Configuring branch protection for 'main' to allow developers to push..."
  
  if [[ -z $PROJECT_ID ]]; then
    echo "Error: Project ID is not set. Cannot configure branch protection."
    exit 1
  fi

  echo "Unprotecting branch 'main'..."
  curl -s --request DELETE \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/protected_branches/main"

  echo "Reapplying branch protection..."
  response=$(curl -s --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=main&push_access_level=30&merge_access_level=30" \
    "$GITLAB_URL/api/v4/projects/$PROJECT_ID/protected_branches")

  echo "Branch protection response: $response"

  if echo "$response" | grep -q '"name":"main"'; then
    echo "Branch protection configured successfully. Developers can now push to 'main'."
  else
    echo "Error: Failed to configure branch protection. Response: $response"
    exit 1
  fi
}

# Function to initialize the repository with a default branch
initialize_repository() {
  echo "Initializing repository with default branch 'main'..."
  TMP_INIT_DIR=$(mktemp -d)
  cd "$TMP_INIT_DIR"
  execute git init
  AUTHENTICATED_REPO_URL="${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
  execute git remote add origin "$AUTHENTICATED_REPO_URL"
  execute touch README.md
  execute git add README.md
  execute git commit -m "Initial commit"
  execute git branch -M main
  execute git push -u origin main
  echo "Default branch 'main' initialized."
  cd -
  rm -rf "$TMP_INIT_DIR"
}

# Main Execution
validate_token
delete_repository
create_repository
initialize_repository
configure_branch_protection

echo "All tasks completed successfully."
