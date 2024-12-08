#!/bin/bash

# Variables
NEW_PASSWORD="new_secure_password"       # Replace with a secure password for the admin
TOKEN_NAME="Automated Script Token"     # Name for the new Personal Access Token
TOKEN_SCOPES="api,write_repository,read_api" # Scopes required for the token

echo "Starting GitLab admin reset and token generation..."

# Run Rails console commands to reset admin password and generate a PAT
sudo gitlab-rails console <<EOF
# Find the admin user
admin = User.find_by(username: 'root')
if admin.nil?
  puts "Admin user 'root' not found. Exiting..."
  exit 1
end

# Reset the admin password
admin.password = '$NEW_PASSWORD'
admin.password_confirmation = '$NEW_PASSWORD'
admin.save!
puts "Admin password reset successfully."

# Check if the token already exists
existing_token = admin.personal_access_tokens.find_by(name: '$TOKEN_NAME')
if existing_token
  existing_token.destroy
  puts "Deleted existing token with name '$TOKEN_NAME'."
end

# Generate a new Personal Access Token
new_token = admin.personal_access_tokens.create!(
  name: '$TOKEN_NAME',
  scopes: ['$TOKEN_SCOPES'.split(',')],
  expires_at: nil # You can set an expiration date, e.g., '2024-12-31'
)
new_token.save!
puts "Your new token is: #{new_token.token}"
EOF

echo "Admin password reset and token generation completed."
