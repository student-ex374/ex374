#!/bin/bash

# Variables
REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
GITLAB_URL="https://git.lab.example.com"
WORKSTATION_DIR="/home/student/projects"  # Directory to clone the repository
GITHUB_REPO_URL="https://github.com/sugum2901/web_server.git"
PROJECT_ID=""
TOKEN=""
ADMIN_PASSWORD="new_secure_password"  # Replace with a secure admin password

# Helper function to execute commands with error handling
execute() {
  echo "Running: $*"
  "$@"
  if [[ $? -ne 0 ]]; then
    echo "Error executing: $*"
    exit 1
  fi
}

# Step 1: Reset admin password and generate/fetch token with debugging
reset_admin_and_generate_token() {
  echo "Resetting admin password and generating token via Rails console..."
  TOKEN=$(sudo gitlab-rails runner "
    admin = User.find_by(username: 'root')
    if admin.nil?
      puts 'Error: Admin user not found.'
      exit 1
    end

    # Reset admin password
    admin.password = '$ADMIN_PASSWORD'
    admin.password_confirmation = '$ADMIN_PASSWORD'
    admin.save!
    puts 'Admin password reset successfully.'

    # Check for an existing token
    token = admin.personal_access_tokens.find_by(name: 'Automated Script Token')
    if token && (token.revoked? || token.expired?)
      token.destroy
      token = nil
    end

    # Create a new token if none exists
    if token.nil?
      token = admin.personal_access_tokens.create!(
        name: 'Automated Script Token',
        scopes: [:api, :write_repository, :read_api],
        expires_at: nil
      )
      token.set_token(SecureRandom.hex(20))
      token.save!
    end

    puts token.token
  " 2>/dev/null)

  if [[ -z $TOKEN ]]; then
    echo "Error: Failed to reset admin password or generate token."
    exit 1
  fi

  echo "Token fetched or generated successfully: $TOKEN"

  # Validate the token scopes
  echo "Validating token scopes..."
  curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/personal_access_tokens" | jq .
}

# Step 2: Validate the token
validate_token() {
  echo "Validating Personal Access Token (PAT)..."
  response=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/user")
  if echo "$response" | grep -q '"username"'; then
    echo "PAT validation successful."
  else
    echo "Error: Invalid or insufficiently scoped PAT. Please ensure it has 'api', 'write_repository', and 'read_api' scopes."
    exit 1
  fi
}

# Step 3: Delete repository if it exists
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

# Step 4: Create a new repository
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

# Step 5: Configure branch protection
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

# Step 6: Clone and push GitHub repo content to GitLab
push_github_to_gitlab() {
  echo "Cloning GitHub repository '$GITHUB_REPO_URL'..."
  TMP_DIR=$(mktemp -d)
  execute git clone "$GITHUB_REPO_URL" "$TMP_DIR"

  echo "Pushing contents to GitLab repository '$REPO_NAME'..."
  cd "$TMP_DIR"
  AUTHENTICATED_REPO_URL="${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
  execute git remote rm origin
  execute git remote add origin "$AUTHENTICATED_REPO_URL"
  execute git branch -M main
  execute git push origin main -f
  cd -
  rm -rf "$TMP_DIR"
}

# Main Execution
reset_admin_and_generate_token
validate_token
delete_repository
create_repository
configure_branch_protection
push_github_to_gitlab

echo "All tasks completed successfully."
