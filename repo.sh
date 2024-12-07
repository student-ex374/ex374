#!/bin/bash

# Variables
REPO_NAME="web_server"
USER_USERNAME="student"  # GitLab username
VISIBILITY="private"     # 'private', 'internal', or 'public'
GITLAB_URL="https://git.lab.example.com"
WORKSTATION_DIR="/home/student/projects"  # Directory to clone the repository
TOKEN="auto-clone-token-123"  # Replace with a secure random token if required
GITHUB_REPO_URL="https://github.com/sugum2901/web_server.git"

# Function to suppress output unless there is an error
execute() {
  "$@" >/dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "Error executing: $*"
    exit 1
  fi
}

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
  project.repository.create_if_not_exists
  puts "Repository '$REPO_NAME' created and storage initialized."
else
  puts "Error: #{project.errors.full_messages.join(', ')}"
  exit 1
end

# Generate a Personal Access Token for the user
token = user.personal_access_tokens.find_by(name: 'Automated Clone Token') ||
  user.personal_access_tokens.create!(
    name: 'Automated Clone Token',
    scopes: [:read_repository, :write_repository]
  )
token.set_token('$TOKEN')
token.save
EOF

# Step 3: Clone GitHub Repository and Push to GitLab
echo "Cloning contents from GitHub repository '$GITHUB_REPO_URL'..."
TMP_DIR=$(mktemp -d)
execute git clone "$GITHUB_REPO_URL" "$TMP_DIR"

echo "Configuring GitLab remote and pushing contents..."
cd "$TMP_DIR"
execute git remote rm origin
execute git remote add origin "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}"
execute git branch -M main
execute git fetch origin || execute git push --set-upstream origin main
execute git push origin main -f
cd -

# Clean up temporary GitHub clone
echo "Cleaning up temporary GitHub clone..."
rm -rf "$TMP_DIR"

# Step 4: Clone the Repository on Workstation
echo "Cloning repository to '$WORKSTATION_DIR/$REPO_NAME'..."
mkdir -p "$WORKSTATION_DIR"
cd "$WORKSTATION_DIR"
execute git clone "${GITLAB_URL/${GITLAB_URL#https://}/$USER_USERNAME:$TOKEN@${GITLAB_URL#https://}/${USER_USERNAME}/${REPO_NAME}.git}" "$REPO_NAME"

echo "Repository cloned successfully to '$WORKSTATION_DIR/$REPO_NAME'."
