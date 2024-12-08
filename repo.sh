#!/bin/bash

# Variables
REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
GITLAB_URL="https://git.lab.example.com"
TOKEN="your-secure-token-here"  # Replace with the newly generated PAT
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
    echo "Delete request sent. Waiting for deletion to complete..."

    # Wait for deletion to complete
    for i in {1..10}; do
      project_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | grep -oP '"id":\d+' | head -1 | grep -oP '\d+')
      if [[ -z $project_id ]]; then
        echo "Repository successfully deleted."
        break
      fi
      echo "Repository still exists. Retrying in 5 seconds... (Attempt $i)"
      sleep 5
    done

    # If still not deleted after retries, exit with an error
    if [[ -n $project_id ]]; then
      echo "Error: Repository '$REPO_NAME' was not deleted after multiple attempts."
      exit 1
    fi
  else
    echo "Repository does not exist. Skipping deletion."
  fi
}

# Function to create a new repository
create_repository() {
  echo "Creating repository '$REPO_NAME'..."
  namespace_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/namespaces?search=$USER_USERNAME" | grep -oP '"id":\d+' | head -1 | grep -oP '\d+')
  if [[ -z $namespace_id ]]; then
    echo "Error: Could not determine namespace ID for user '$USER_USERNAME'."
    exit 1
  fi

  echo "Namespace ID: $namespace_id"

  response=$(curl -s --request POST "$GITLAB_URL/api/v4/projects" \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=$REPO_NAME&namespace_id=$namespace_id&visibility=private")

  echo "Repository creation response: $response"

  if echo "$response" | grep -q '"id":'; then
    echo "Repository created successfully."
  else
    echo "Error creating repository. Response: $response"
    exit 1
  fi
}

configure_branch_protection() {
  echo "Configuring branch protection for 'main' to allow developers to push..."
  project_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | jq -r '.[0].id')

  if [[ -z $project_id ]]; then
    echo "Error: Could not determine project ID for '$REPO_NAME'."
    exit 1
  fi

  # Remove existing branch protection
  echo "Unprotecting branch 'main'..."
  curl -s --request DELETE \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/projects/$project_id/protected_branches/main"

  # Configure new branch protection
  echo "Reconfiguring branch protection for 'main'..."
  response=$(curl -s --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=main&push_access_level=30&merge_access_level=30" \
    "$GITLAB_URL/api/v4/projects/$project_id/protected_branches")

  echo "Branch protection response: $response"

  if echo "$response" | grep -q '"name":"main"'; then
    echo "Branch protection configured successfully. Developers can now push to 'main'."
  else
    echo "Error: Failed to configure branch protection. Response: $response"
    exit 1
  fi
}

# Function to unprotect the branch
unprotect_branch() {
  echo "Unprotecting branch 'main'..."
  project_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | grep -oP '"id":\d+' | head -1 | grep -oP '\d+')
  if [[ -z $project_id ]]; then
    echo "Error: Could not determine project ID for '$REPO_NAME'."
    exit 1
  fi
  curl -s --request DELETE \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/projects/$project_id/protected_branches/main" || {
    echo "Warning: Branch 'main' may not be protected yet."
  }
  echo "Branch 'main' unprotected."
}

# Function to re-protect the branch
protect_branch() {
  echo "Re-protecting branch 'main'..."
  project_id=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects?search=$REPO_NAME" | grep -oP '"id":\d+' | head -1 | grep -oP '\d+')
  if [[ -z $project_id ]]; then
    echo "Error: Could not determine project ID for '$REPO_NAME'."
    exit 1
  fi
  curl -s --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=main&push_access_level=0&merge_access_level=0" \
    "$GITLAB_URL/api/v4/projects/$project_id/protected_branches"
  echo "Branch 'main' re-protected."
}

# Function to initialize the repository with a default branch
initialize_repository() {
  echo "Initializing repository with default branch 'main'..."
  TMP_INIT_DIR=$(mktemp -d)
  cd "$TMP_INIT_DIR"
  execute git init
  execute git remote add origin "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
  execute touch README.md
  execute git add README.md
  execute git commit -m "Initial commit"
  execute git branch -M main
  execute git push -u origin main
  echo "Default branch 'main' initialized."
  cd -
  rm -rf "$TMP_INIT_DIR"
}

# Function to push GitHub repository contents to GitLab
push_github_to_gitlab() {
  echo "Cloning GitHub repository '$GITHUB_REPO_URL'..."
  TMP_DIR=$(mktemp -d)
  execute git clone "$GITHUB_REPO_URL" "$TMP_DIR"

  echo "Unprotecting branch 'main' for force push..."
  unprotect_branch

  echo "Pushing contents to GitLab repository '$REPO_NAME'..."
  cd "$TMP_DIR"
  execute git remote rm origin
  execute git remote add origin "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
  execute git push origin main -f

  echo "Re-protecting branch 'main' after force push..."
  protect_branch

  cd -
  rm -rf "$TMP_DIR"
}

# Function to clone the GitLab repository locally
clone_gitlab_repo() {
  echo "Cloning GitLab repository to '$WORKSTATION_DIR/$REPO_NAME'..."
  
  # Check if the directory exists
  if [[ -d "$WORKSTATION_DIR/$REPO_NAME" ]]; then
    if [[ -z "$(ls -A "$WORKSTATION_DIR/$REPO_NAME")" ]]; then
      echo "Directory exists but is empty. Proceeding with clone."
    else
      echo "Directory exists and is not empty. Cleaning up directory..."
      rm -rf "$WORKSTATION_DIR/$REPO_NAME"
    fi
  fi
  
  mkdir -p "$WORKSTATION_DIR"
  execute git clone "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}" "$WORKSTATION_DIR/$REPO_NAME"
  echo "Repository cloned successfully."
}


# Main Execution
validate_token
delete_repository
create_repository
initialize_repository
configure_branch_protection
push_github_to_gitlab
clone_gitlab_repo

echo "All tasks completed successfully."
