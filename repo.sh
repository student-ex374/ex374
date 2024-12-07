#!/bin/bash

# Variables new
REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
VISIBILITY="private"     # 'private', 'internal', or 'public'
GITLAB_URL="https://git.lab.example.com"
WORKSTATION_DIR="/home/student/projects"  # Directory to clone the repository
TOKEN="auto-clone-token-123"  # Replace with a secure random token if required

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

# Step 1: Delete the Repository if it Exists
echo "Checking if repository '$REPO_NAME' already exists..."
gitlab-rails console <<EOF
user = User.find_by_username('$USER_USERNAME')
if user.nil?
  puts "Error: User '$USER_USERNAME' not found."
  exit 1
end

project = user.namespace.projects.find_by(path: '$REPO_NAME')
if project
  project.destroy
  puts "Repository '$REPO_NAME' deleted successfully."
else
  puts "Repository '$REPO_NAME' not found. Skipping deletion."
end
EOF

if [[ $? -ne 0 ]]; then
  echo "Failed to delete the repository. Please check the error logs."
  exit 1
fi

# Step 2: Create the Repository
echo "Creating repository '$REPO_NAME' for user '$USER_USERNAME'..."

gitlab-rails console <<EOF
user = User.find_by_username('$USER_USERNAME')
if user.nil?
  puts "Error: User '$USER_USERNAME' not found."
  exit 1
end

project = Project.new(
  name: '$REPO_NAME',
  path: '$REPO_NAME',
  namespace: user.namespace,
  visibility_level: Gitlab::VisibilityLevel::PRIVATE
)

project.creator = user
if project.save
  puts "Repository '$REPO_NAME' created successfully."
else
  puts "Error: #{project.errors.full_messages.join(', ')}"
  exit 1
end

# Generate a Personal Access Token for the user
token = user.personal_access_tokens.create!(
  name: 'Automated Clone Token',
  scopes: [:read_repository, :write_repository]
)
token.set_token('$TOKEN')  # Assign the provided token
token.save
puts "Personal Access Token: #{token.token}"
EOF

if [[ $? -ne 0 ]]; then
  echo "Failed to create repository or generate access token."
  exit 1
fi

# Step 3: Initialize Repository and Push Initial Commit
echo "Initializing repository with an initial commit..."

TMP_DIR=$(mktemp -d)
GIT_CLONE_URL="${GITLAB_URL}/${USER_USERNAME}/${REPO_NAME}.git"
git clone "${GIT_CLONE_URL}" "$TMP_DIR" --quiet --config http.extraHeader="Authorization: Bearer $TOKEN"
if [[ $? -ne 0 ]]; then
  echo "Failed to clone the repository. Ensure HTTPS and PAT are configured correctly."
  exit 1
fi

cd "$TMP_DIR"
if [[ ! -f README.md ]]; then
  echo "# $REPO_NAME Project" > README.md
  git add README.md
  git commit -m "Initial commit" --quiet
  git push origin main --quiet
fi
cd -
rm -rf "$TMP_DIR"

# Step 4: Clone the Repository on Workstation
echo "Cloning repository to '$WORKSTATION_DIR/$REPO_NAME'..."

mkdir -p "$WORKSTATION_DIR"
cd "$WORKSTATION_DIR"

git clone "${GIT_CLONE_URL}" "$REPO_NAME" --quiet --config http.extraHeader="Authorization: Bearer $TOKEN"
if [[ $? -eq 0 ]]; then
  echo "Repository cloned successfully to '$WORKSTATION_DIR/$REPO_NAME'."
else
  echo "Failed to clone the repository."
  exit 1
fi
