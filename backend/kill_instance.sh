#!/bin/bash

# Check if an instance ID was provided
if [ $# -eq 0 ]; then
    echo "Error: No instance ID provided"
    echo "Usage: \$0 <instance-id>"
    exit 1
fi

INSTANCE_ID="$1"

# Set AWS region (you can also set this as an environment variable)
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Terminating instance $INSTANCE_ID in region $AWS_REGION..."

# Terminate the instance
if aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" >/dev/null; then
    echo "Instance termination initiated successfully."

    # Wait for the instance to be terminated
    echo "Waiting for instance to be terminated..."
    if aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"; then
        echo "Instance $INSTANCE_ID has been successfully terminated."
    else
        echo "Error: Failed to confirm instance termination. Please check the AWS console."
    fi
else
    echo "Error: Failed to initiate instance termination. Please check the instance ID and your AWS credentials."
    exit 1
fi
