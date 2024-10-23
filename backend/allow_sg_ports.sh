#!/bin/bash

# Read security group ID from environment variable
if [ -z "${SECURITY_GROUP_ID}" ]; then
    echo "Error: SECURITY_GROUP_ID environment variable is not set"
    exit 1
fi

AWS_REGION="us-east-1"

# Array of ports to open
PORTS=(5900 8501 6080 8080)

# Loop through each port and add an inbound rule
for PORT in "${PORTS[@]}"; do
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port $PORT \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION

    echo "Added inbound rule for port $PORT"
done

echo "Security group updated successfully."
