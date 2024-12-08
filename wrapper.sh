#!/bin/bash

# Step 1: Run token.sh to generate the token
echo "Generating token using token.sh..."
TOKEN=$(bash token.sh | grep 'Your new token is:' | awk -F: '{print $NF}' | sed 's/^\s//')

# Check if the token was generated successfully
if [[ -z $TOKEN ]]; then
  echo "Error: Token generation failed."
  exit 1
fi

echo "Token generated successfully: $TOKEN"

# Step 2: Run repo.sh with the generated token
echo "Running repo.sh with the generated token..."
bash repo.sh "$TOKEN"

if [[ $? -eq 0 ]]; then
  echo "Repository setup completed successfully."
else
  echo "Error: Repository setup failed."
  exit 1
fi
