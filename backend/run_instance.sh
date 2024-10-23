#!/bin/bash

# Set AWS configuration variables
AWS_REGION="${AWS_REGION:-us-east-1}"       # Load from environment or fall back to us-east-1
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}" # Load from environment or fall back to t3.medium

if [ -z "${KEY_NAME}" ]; then
    echo "Error: KEY_NAME environment variable is not set"
    exit 1
fi

if [ -z "${SECURITY_GROUP_ID}" ]; then
    echo "Error: SECURITY_GROUP_ID environment variable is not set"
    exit 1
fi

# Parse command line arguments
# -f flag enables force run mode which will actually launch the instance
FORCE_RUN=false
while getopts "f" opt; do
    case $opt in
    f)
        FORCE_RUN=true
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
    esac
done

# Verify that the Anthropic API key is set in the environment
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY is not set in the environment."
    exit 1
fi

echo "Creating user data script..."

# Generate the user data script for EC2 instance initialization
cat <<'EOF' >user_data.sh
#!/bin/bash

# Update system and install required packages
yum update -y
amazon-linux-extras install docker -y
sudo yum install -y xorg-x11-xauth xorg-x11-server-utils xorg-x11-server-Xvfb

# Initialize X virtual framebuffer (Xvfb)
Xvfb :1 -screen 0 1024x768x24 -ac +extension MIT-SHM &
export DISPLAY=:1

# Configure X server permissions
sleep 2
xhost +local:
xhost +SI:localuser:root
xhost +local:docker 

# Initialize and configure Docker
systemctl start docker
systemctl enable docker

# Allow Docker to connect to X server
xhost +local:docker

# Prepare directory for Docker logs
mkdir -p /var/log/anthropic-demo

# Pull and run the Anthropic demo Docker image
docker pull ghcr.io/anthropics/anthropic-quickstarts:computer-use-demo-latest
docker run -d \
    --name computer-use-demo \
    -p 5900:5900 \
    -p 8501:8501 \
    -p 6080:6080 \
    -p 8080:8080 \
    -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    -e DISPLAY=:1 \
    -e STREAMLIT_SERVER_HEADLESS=true \
    -v /var/log/anthropic-demo:/home/computeruse/.anthropic \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /dev/shm:/dev/shm \
    --ipc=host \
    --log-driver json-file \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    ghcr.io/anthropics/anthropic-quickstarts:computer-use-demo-latest

# Allow time for container initialization
sleep 5

# Ensure VNC server is running within the container
docker exec computer-use-demo bash -c "x11vnc -display :1 -forever -noxdamage -repeat -shared &"

# Configure log rotation for Docker containers
cat <<EOT > /etc/logrotate.d/docker-containers
/var/lib/docker/containers/*/*.log {
    rotate 7
    daily
    compress
    missingok
    delaycompress
    copytruncate
}
EOT

# Retrieve the instance's public IP address
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Update demo application with correct IP address
docker exec computer-use-demo bash -c "sed -i 's/localhost/$PUBLIC_IP/g' /home/computeruse/static_content/index.html"
docker exec computer-use-demo bash -c "sed -i 's/127.0.0.1/$PUBLIC_IP/g' /home/computeruse/static_content/index.html"

# Apply changes by restarting the container
docker restart computer-use-demo

# Allow time for container restart
sleep 5

# Reinitialize X server and window manager after container restart
docker exec computer-use-demo bash -c '
    export DISPLAY=:1
    xhost +local:
    xhost +SI:localuser:root
    Xvfb :1 -screen 0 1024x768x24 -ac +extension MIT-SHM &
    sleep 2
    xauth generate :1 . trusted
    tint2 &
'

# Ensure VNC server is running after container restart
docker exec computer-use-demo bash -c "x11vnc -display :1 -forever -noxdamage -repeat -shared &"

EOF

# Insert the actual ANTHROPIC_API_KEY into the user data script
# Note: This sed command is compatible with both Linux and macOS
sed -i.bak "s|\${ANTHROPIC_API_KEY}|$ANTHROPIC_API_KEY|g" user_data.sh && rm user_data.sh.bak

echo "User data script created."

# Fetch the latest Amazon Linux 2 AMI ID
echo "Fetching latest Amazon Linux 2 AMI ID..."
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-2.0.????????.?-x86_64-gp2" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text --region $AWS_REGION)
echo "Latest Amazon Linux 2 AMI ID: $AMI_ID"

# Construct the base AWS CLI command for launching an EC2 instance
BASE_COMMAND="aws ec2 run-instances \
    --image-id \"$AMI_ID\" \
    --instance-type \"$INSTANCE_TYPE\" \
    --key-name \"$KEY_NAME\" \
    --security-group-ids \"$SECURITY_GROUP_ID\" \
    --user-data file://user_data.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ComputerUseDemo}]'"

if [ "$FORCE_RUN" = true ]; then
    # Execute the EC2 instance launch if force run is enabled
    echo "Launching EC2 instance..."
    INSTANCE_INFO=$(eval "$BASE_COMMAND")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | jq -r '.Instances[0].InstanceId')
    echo "EC2 instance launched. Instance ID: $INSTANCE_ID"

    # Wait for the instance to reach the 'running' state
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    # Retrieve and display instance details
    echo "Getting instance details..."
    INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID")
    PUBLIC_IP=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
    PUBLIC_DNS=$(echo "$INSTANCE_DETAILS" | jq -r '.Reservations[0].Instances[0].PublicDnsName')

    # Output instance details as JSON
    echo "{\"InstanceId\": \"$INSTANCE_ID\", \"PublicIpAddress\": \"$PUBLIC_IP\", \"PublicDnsName\": \"$PUBLIC_DNS\"}"
else
    # Perform a dry run if force run is not enabled
    echo "Performing dry run..."
    DRY_RUN_OUTPUT=$(eval "$BASE_COMMAND --dry-run" 2>&1)
    echo "Dry run completed. Here's what would have been created:"
    echo "$DRY_RUN_OUTPUT"
    echo "To launch the instance, run this script with the -f flag: ./run_instance.sh -f"
fi
