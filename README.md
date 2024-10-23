# EC2 Instance Launcher for Anthropic Computer Use Demo

This script automates the deployment of an EC2 instance running the Anthropic Computer Use Demo in a Docker container.
This will use the latest image from the [Anthropic quickstart demo](https://github.com/anthropics/anthropic-quickstarts/pkgs/container/anthropic-quickstarts)
As of the time of publishing, this is ghcr.io/anthropics/anthropic-quickstarts:computer-use-demo-a306792

## Prerequisites

1. **AWS CLI**: Must be installed and configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **AWS Access**:
   - An AWS account with EC2 permissions
   - A security group
   - An SSH key pair

3. **Anthropic API Key**:
   - A valid Anthropic API key
   - Must be set as an environment variable:
     ```bash
     export ANTHROPIC_API_KEY='your-api-key-here'
     ```

## Initial Setup

1. Configure Security Group Ports:
   ```bash
   # Edit allow_sg_ports script with your security group ID and region
   vim allow_sg_ports.sh
   
   # Make the script executable
   chmod +x allow_sg_ports.sh
   
   # Run the script to open required ports
   ./allow_sg_ports.sh
   ```

2. Update `run_instance.sh` with your configuration:
   ```bash
   # Edit these variables in run_instance.sh:
   AWS_REGION="your-region"
   INSTANCE_TYPE="your-instance-type"
   KEY_NAME="your-key-name"
   SECURITY_GROUP_ID="your-security-group-id"
   ```

## Usage

1. Make the script executable:
   ```bash
   chmod +x run_instance.sh
   ```

2. Run a dry run (no instance created):
   ```bash
   ./run_instance.sh
   ```

3. Actually launch the instance:
   ```bash
   ./run_instance.sh -f
   ```

## What Gets Deployed

The script will:
1. Launch an EC2 instance with Amazon Linux 2
2. Install Docker and X11 utilities
3. Pull and run the Anthropic demo Docker container
4. Configure VNC server and necessary networking
5. Set up log rotation

## Accessing the Demo

After successful deployment, the script will output:
- Public IP address
- Public DNS name
- URL to access the demo (http://[PUBLIC_IP]:8080)
- SSH command to connect to the instance

## SSH Access

Use the provided SSH command to connect to the instance:
```bash
ssh -i "path/to/your-key.pem" ec2-user@[PUBLIC_DNS]
```

Make sure your SSH key has appropriate permissions:
```bash
chmod 400 path/to/your-key.pem
```

## Ports Used

The following ports are automatically configured by `allow_sg_ports`:
- 5900: VNC server
- 8501: Streamlit
- 6080: noVNC
- 8080: Main demo application

## Security Considerations

The `allow_sg_ports` script will configure your security group to allow:
- Required application ports (5900, 8501, 6080, 8080)
- Access from any IP (0.0.0.0/0)

## Cleanup

To avoid unnecessary charges, remember to terminate the EC2 instance when done:
```bash
aws ec2 terminate-instances --instance-ids [INSTANCE_ID]
```

## Troubleshooting

1. If the script fails with an API key error:
   - Verify ANTHROPIC_API_KEY is set correctly
   - Check API key validity

2. If instance launch fails:
   - Verify AWS credentials
   - Check security group exists
   - Ensure SSH key pair exists

3. If demo is inaccessible:
   - Verify security group ports were opened successfully
   - Wait a few minutes for full initialization
   - Check instance logs via AWS Console
