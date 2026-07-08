# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Version 1.0.5

import asyncio
import logging
import os
import mcp.types as types
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.requests import Request
from starlette.responses import PlainTextResponse
import httpx
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastMCP with disabled DNS rebinding protection for Cloud Run (enabling json_response for Streamable HTTP)
mcp = FastMCP(
    "Weather Server",
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    json_response=True,
)

GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_URL = "https://api.open-meteo.com/v1/forecast"

# Startup Probe Warmup Configuration
WARMUP_TARGET_URL = "https://www.google.com/humans.txt"
WARMUP_DONE = False
MAX_WARMUP_ATTEMPTS = 3
WARMUP_DELAY = 1.0


async def attempt_external_connection() -> bool:
    """
    Attempt connecting to external endpoint to warm up network path / NAT mapping.
    Once successful, sets WARMUP_DONE to True so subsequent checks return immediately.
    """
    global WARMUP_DONE
    if WARMUP_DONE:
        return True

    for attempt in range(1, MAX_WARMUP_ATTEMPTS + 1):
        try:
            logger.info(
                f"Startup probe warmup attempt {attempt}/{MAX_WARMUP_ATTEMPTS}: "
                f"Connecting to {WARMUP_TARGET_URL}"
            )
            async with httpx.AsyncClient(timeout=3.0) as client:
                response = await client.get(WARMUP_TARGET_URL)
                response.raise_for_status()
                logger.info("Startup probe warmup connection successful!")
                WARMUP_DONE = True
                return True
        except Exception as e:
            logger.warning(f"Startup probe warmup attempt {attempt} failed: {e}")
            if attempt < MAX_WARMUP_ATTEMPTS:
                await asyncio.sleep(WARMUP_DELAY)

    logger.error("Startup probe warmup failed after multiple attempts.")
    return False


@mcp.tool(
    annotations=types.ToolAnnotations(
        readOnly=True,
        destructive=False,
        idempotent=True,
        openWorld=False,
    )
)
async def get_weather(location: str) -> str:
    """
    Fetch weather for a given location.

    Args:
        location (str): The name of the city/location (e.g., "Paris", "New York").
    """
    if not location:
        return "Error: Location parameter is required."

    logger.info(f"Fetching weather for location: {location}")

    async with httpx.AsyncClient() as client:
        # 1. Geocoding: Get Lat/Lon
        try:
            geo_response = await client.get(
                GEOCODING_URL,
                params={"name": location, "count": 1, "language": "en", "format": "json"}
            )
            geo_response.raise_for_status()
            geo_data = geo_response.json()
        except Exception as e:
            logger.error(f"Geocoding error: {e}")
            return f"Error resolving location: {str(e)}"

        if not geo_data.get("results"):
            return f"Error: Location '{location}' not found."

        result = geo_data["results"][0]
        lat = result["latitude"]
        lon = result["longitude"]
        resolved_name = result.get("name", location)
        country = result.get("country", "")

        # 2. Weather: Get Current Weather
        try:
            weather_response = await client.get(
                WEATHER_URL,
                params={
                    "latitude": lat,
                    "longitude": lon,
                    "current_weather": True,
                    "temperature_unit": "celsius"
                }
            )
            weather_response.raise_for_status()
            weather_data = weather_response.json()
        except Exception as e:
            logger.error(f"Weather fetch error: {e}")
            return f"Error fetching weather data: {str(e)}"

        current = weather_data.get("current_weather")
        if not current:
            return "Error: Weather data unavailable."

        return (
            f"The current temperature in {resolved_name}, {country} is "
            f"{current['temperature']}°C with a windspeed of {current['windspeed']} km/h."
        )


# Get the Starlette app for Streamable HTTP
app = mcp.streamable_http_app()



async def warmup(request: Request):
    """
    Startup probe endpoint called by Cloud Run during instance initialization.
    Returns 200 OK after successful external connectivity check, or 503 on failure.
    """
    if await attempt_external_connection():
        return PlainTextResponse("Warmup OK", status_code=200)
    else:
        return PlainTextResponse("Warmup Failed: Cannot reach external network", status_code=503)


# Register startup probe route on Starlette app
app.add_route("/warmup", warmup, methods=["GET"])

if __name__ == "__main__":
    # Run the app using uvicorn (respecting PORT env var set by Cloud Run)
    port = int(os.getenv("PORT", "8080"))
    logger.info(f"Starting MCP Weather Server on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port)
