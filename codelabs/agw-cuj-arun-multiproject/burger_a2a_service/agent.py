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

from google.adk.agents import LlmAgent
from pydantic import BaseModel
import uuid

class OrderItem(BaseModel):
    name: str
    quantity: int
    price: int

class Order(BaseModel):
    order_id: str
    status: str
    order_items: list[OrderItem]

def create_burger_order(order_items: list[OrderItem]) -> str:
    """Creates a new burger order with the given order items.

    Args:
        order_items: List of order items to be added to the order.
    """
    try:
        order_id = str(uuid.uuid4())
        order = Order(order_id=order_id, status="created", order_items=order_items)
        return f"Order {order.model_dump()} has been created successfully. Order ID: {order_id}"
    except Exception as e:
        return f"Error creating order: {e}"

def get_burger_menu() -> str:
    """Retrieves the full menu of available burgers and their prices in IDR."""
    return """Available Burger Menu:
- Classic Cheeseburger: IDR 85,000
- Double Cheeseburger: IDR 110,000
- Spicy Chicken Burger: IDR 80,000
- Spicy Cajun Burger: IDR 85,000"""

burger_agent = LlmAgent(
    name="burger_seller_agent",
    model="gemini-2.5-flash",
    instruction="""
You are a specialized assistant for a burger store.
Your sole purpose is to answer questions about what is available on burger menu and price also handle order creation.
If the user asks about anything other than burger menu or order creation, politely state that you cannot help with that topic and can only assist with burger menu and order creation.
Do not attempt to answer unrelated questions or use tools for other purposes.

Provided below is the available burger menu and it's related price:
- Classic Cheeseburger: IDR 85K
- Double Cheeseburger: IDR 110K
- Spicy Chicken Burger: IDR 80K
- Spicy Cajun Burger: IDR 85K

Rules:
1. Always verify the burger item requested is in the menu.
2. When the user confirms an order, invoke create_burger_order.
""",
    tools=[get_burger_menu, create_burger_order]
)
