"""
This is the backend for the Anthropic Computer Use Demo.
It is a simple FastAPI app that launches an EC2 instance and returns the instance details.
"""

import asyncio
import json
import subprocess
import time
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, computed_field

# Configure logging
logging.basicConfig(
    filename="app.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)

app = FastAPI()


class InstanceDetails(BaseModel):
    """
    The details of the instance that were created.
    """

    instance_id: str = Field(description="The ID of the instance that was created.")
    public_ip: str = Field(description="The public IP address of the instance.")
    public_dns: str = Field(description="The public DNS name of the instance.")

    @computed_field(description="The URL to access the Computer Use Demo.")
    @property
    def url(self) -> str:
        """
        The URL to access the Computer Use Demo.
        """
        return f"http://{self.public_dns}:8080"


@app.post("/launch", response_model=InstanceDetails)
async def launch():
    """
    Launch an EC2 instance and return the instance details.
    """
    try:
        # Run the run_instance.sh script with the -f flag
        logging.info("Launching instance...")
        start_time = time.time()
        result = subprocess.run(
            ["./run_instance.sh", "-f"], capture_output=True, text=True, check=True
        )
        end_time = time.time()

        # Calculate and log the launch duration
        launch_duration = end_time - start_time
        logging.info("Instance launch completed in %.2f seconds" % launch_duration)

        # Parse the output to extract instance details
        instance_details = json.loads(result.stdout.strip().split("\n")[-1])

        res = InstanceDetails(
            instance_id=instance_details["InstanceId"],
            public_ip=instance_details["PublicIpAddress"],
            public_dns=instance_details["PublicDnsName"],
        )
        logging.info("Instance details: %s", res)
        return res

    except subprocess.CalledProcessError as e:
        logging.error("Failed to launch instance: %s", str(e.stderr))
        raise HTTPException(
            status_code=500, detail="Failed to launch instance: %s" % str(e.stderr)
        ) from e
    except json.JSONDecodeError as e:
        logging.error("Failed to parse instance details: %s", str(e))
        raise HTTPException(
            status_code=500, detail="Failed to parse instance details: %s" % str(e)
        ) from e
    except KeyError as e:
        logging.error("Missing expected data in instance details: %s", str(e))
        raise HTTPException(
            status_code=500,
            detail="Missing expected data in instance details: %s" % str(e),
        ) from e


class InstanceTerminationRequest(BaseModel):
    """
    The request to terminate an EC2 instance.
    """

    instance_id: str = Field(description="The ID of the instance to terminate.")


class InstanceTerminationResponse(BaseModel):
    """
    The response to terminating an EC2 instance.
    """

    message: str = Field(
        description="A message indicating the status of the termination."
    )
    details: str = Field(
        description="Details about the termination process, such as the instance ID."
    )


async def terminate_instance(instance_id: str):
    """
    Terminate an EC2 instance and log the results.
    """
    try:
        logging.info(f"Terminating instance {instance_id}...")
        start_time = time.time()
        result = await asyncio.create_subprocess_exec(
            "./kill_instance.sh",
            instance_id,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await result.communicate()
        end_time = time.time()

        # Calculate and log the termination duration
        termination_duration = end_time - start_time
        logging.info(
            f"Instance termination completed in {termination_duration:.2f} seconds"
        )

        if result.returncode == 0:
            termination_details = stdout.decode().strip()
            logging.info(f"Termination details: {termination_details}")
            logging.info(f"Instance {instance_id} terminated successfully")
        else:
            error_message = stderr.decode().strip()
            logging.error(f"Failed to terminate instance: {error_message}")

    except Exception as e:
        logging.error(f"Error during instance termination: {str(e)}")


@app.post("/kill", response_model=InstanceTerminationResponse)
async def kill_instance(instance_data: InstanceTerminationRequest):
    """
    Initiate EC2 instance termination in the background and return immediately.
    """
    logging.info(f"Initiating termination for instance {instance_data.instance_id}...")

    # Start the termination process in the background
    asyncio.create_task(terminate_instance(instance_data.instance_id))

    return InstanceTerminationResponse(
        message=f"Termination process initiated for instance {instance_data.instance_id}",
        details="Termination is running in the background. Check logs for completion status.",
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
