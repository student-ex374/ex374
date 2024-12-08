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

# Step 1: Generate token manually
generate_token() {
  echo "Generating token via Rails console..."
  TOKEN=$(sudo gitlab-rails runner "
    admin = User.find_by(username: 'root')
    if admin.nil?
      puts 'Error: Admin user not found.'
      exit 1
    end

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
    echo "Error: Failed to generate token."
    exit 1
  fi

  echo "Token generated successfully: $TOKEN"
}

# Step 2: Delete repository if it exists
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

# Step 3: Create a new repository
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

# Step 4: Push GitHub repo content to GitLab
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
generate_token
delete_repository
create_repository
push_github_to_gitlab

echo "All tasks completed successfully."
