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

import asyncio
import functools
import logging
import os
import click
import uvicorn

from a2a.server.apps import A2AStarletteApplication
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentSkill,
)
from agent import burger_agent
from agent_executor import ADKAgentExecutor
from starlette.applications import Starlette

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "True"
if not os.getenv("GOOGLE_CLOUD_PROJECT"):
    os.environ["GOOGLE_CLOUD_PROJECT"] = "deepakmichaelprod"
if not os.getenv("GOOGLE_CLOUD_LOCATION"):
    os.environ["GOOGLE_CLOUD_LOCATION"] = "us-central1"

def make_sync(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        return asyncio.run(func(*args, **kwargs))
    return wrapper

@click.command()
@click.option('--host', default='0.0.0.0')
@click.option('--port', default=8080, type=int)
@make_sync
async def main(host, port):
    app_url = os.environ.get('APP_URL', f'http://{host}:{port}')

    agent_name = os.environ.get('AGENT_NAME', 'Burger Seller Agent')
    agent_card = AgentCard(
        name=agent_name,
        description="Specialized seller agent for browsing burger menus, checking pricing, and placing orders.",
        version='1.0.0',
        url=app_url,
        default_input_modes=['text', 'text/plain'],
        default_output_modes=['text', 'text/plain'],
        capabilities=AgentCapabilities(streaming=True),
        skills=[
            AgentSkill(
                id='get_burger_menu',
                name='get_burger_menu',
                description='Retrieves the full menu of available burgers and their prices in IDR.',
                tags=['menu', 'food', 'pricing'],
                examples=[
                    'What burgers are available?',
                    'Can I see the burger menu and prices?'
                ],
            ),
            AgentSkill(
                id='create_burger_order',
                name='create_burger_order',
                description='Places an order for one or more burger menu items and returns an order confirmation ID.',
                tags=['order', 'food', 'burger', 'checkout'],
                examples=[
                    'Order 1 Classic Cheeseburger',
                    'I would like to order 2 Double Cheeseburgers'
                ],
            ),
        ],
    )

    request_handler = DefaultRequestHandler(
        agent_executor=ADKAgentExecutor(
            agent=burger_agent,
        ),
        task_store=InMemoryTaskStore(),
    )

    a2a_app = A2AStarletteApplication(
        agent_card=agent_card, http_handler=request_handler
    )
    routes = a2a_app.routes()
    app = Starlette(
        routes=routes,
        middleware=[],
    )

    config = uvicorn.Config(app, host=host, port=port, log_level='info')
    server = uvicorn.Server(config)
    await server.serve()

if __name__ == '__main__':
    main()
