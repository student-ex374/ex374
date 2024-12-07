#!/bin/bash

# Variables
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

# Function to check token permissions
check_token_permissions() {
  echo "Checking Personal Access Token (PAT) permissions..."
  permissions=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/personal_access_tokens")
  if [[ -z $permissions ]]; then
    echo "Error: Invalid or insufficiently scoped Personal Access Token."
    echo "Please ensure your token has 'api', 'read_api', and 'write_repository' scopes."
    exit 1
  fi
  echo "Token is valid and has sufficient permissions."
}

# Function to retrieve the namespace ID for the user
get_namespace_id() {
  echo "Retrieving namespace ID for user '$USER_USERNAME'..."
  curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/namespaces?search=$USER_USERNAME" | \
  grep -oP '"id":\d+,"name":"'$USER_USERNAME'"' | grep -oP '\d+' | head -1
}

# Function to create the repository using the GitLab API
create_repository() {
  echo "Creating repository '$REPO_NAME'..."
  local namespace_id
  namespace_id=$(get_namespace_id)
  if [[ -z $namespace_id ]]; then
    echo "Error: Could not determine namespace ID for user '$USER_USERNAME'."
    exit 1
  fi
  curl -s --request POST "$GITLAB_URL/api/v4/projects" \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=$REPO_NAME&namespace_id=$namespace_id&visibility=private" || {
    echo "Error creating repository '$REPO_NAME'."
    exit 1
  }
}

# Function to set the default branch using the GitLab API
set_default_branch() {
  local branch_name=$1
  echo "Setting default branch '$branch_name' for repository '$REPO_NAME'..."
  curl -s --request PUT \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "default_branch=$branch_name" \
    "$GITLAB_URL/api/v4/projects/$(echo $USER_USERNAME/$REPO_NAME | sed 's/\//%2F/g')"
}

# Function to delete the repository using the GitLab API
delete_repository() {
  echo "Deleting repository '$REPO_NAME'..."
  curl -s --request DELETE \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/projects/$(echo $USER_USERNAME/$REPO_NAME | sed 's/\//%2F/g')"
}

# Step 1: Check token permissions
check_token_permissions

# Step 2: Delete the repository if it exists
echo "Checking if repository '$REPO_NAME' exists..."
if curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | grep -q "\"path\":\"$REPO_NAME\""; then
  delete_repository
fi

# Step 3: Create the repository
create_repository

# Step 4: Initialize Repository with Default Branch
TMP_INIT_DIR=$(mktemp -d)
cd "$TMP_INIT_DIR"
execute git init
execute git remote add origin "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
execute touch README.md
execute git add README.md
execute git commit -m "Initialize repository"
execute git branch -M main

# Push initial commit to create the branch
execute git push -u origin main

# Set default branch in GitLab
set_default_branch "main"

cd -
rm -rf "$TMP_INIT_DIR"

# Step 5: Clone GitHub Repository and Push to GitLab
echo "Cloning contents from GitHub repository '$GITHUB_REPO_URL'..."
TMP_DIR=$(mktemp -d)
execute git clone "$GITHUB_REPO_URL" "$TMP_DIR"

echo "Pushing contents to GitLab repository '$REPO_NAME'..."
cd "$TMP_DIR"
execute git remote rm origin
execute git remote add origin "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
execute git push origin main -f
cd -

# Clean up temporary GitHub clone
rm -rf "$TMP_DIR"

# Step 6: Clone the Repository on Workstation
mkdir -p "$WORKSTATION_DIR"
cd "$WORKSTATION_DIR"
execute git clone "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}" "$REPO_NAME"

echo "Repository cloned successfully to '$WORKSTATION_DIR/$REPO_NAME'."
