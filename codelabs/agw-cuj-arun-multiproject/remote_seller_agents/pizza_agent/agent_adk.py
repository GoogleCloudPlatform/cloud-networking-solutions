# Monkey-patch ADK Runner to force auto-creation of sessions
try:
    from google.adk import runners
    original_init = runners.Runner.__init__
    def patched_init(self, *args, **kwargs):
        kwargs['auto_create_session'] = True
        original_init(self, *args, **kwargs)
    runners.Runner.__init__ = patched_init
    print("Successfully monkey-patched ADK Runner to auto_create_session=True")
except Exception as e:
    print(f"Failed to monkey-patch ADK Runner: {e}")

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

def create_pizza_order(order_items: list[OrderItem]) -> str:
    """Creates a new pizza order with the given order items.

    Args:
        order_items: List of order items to be added to the order.
    """
    try:
        order_id = str(uuid.uuid4())
        order = Order(order_id=order_id, status="created", order_items=order_items)
        print("===")
        print(f"order created: {order}")
        print("===")
        return f"Order {order.model_dump()} has been created"
    except Exception as e:
        return f"Error creating order: {e}"

pizza_agent = LlmAgent(
    name="pizza_seller_agent",
    model="gemini-2.5-flash-lite",
    instruction="""
You are a specialized assistant for a pizza store.
Your sole purpose is to answer questions about what is available on pizza menu and price also handle order creation.
If the user asks about anything other than pizza menu or order creation, politely state that you cannot help with that topic and can only assist with pizza menu and order creation.
Do not attempt to answer unrelated questions or use tools for other purposes.

Provided below is the available pizza menu and it's related price:
- Margherita Pizza: IDR 100K
- Pepperoni Pizza: IDR 140K
- Hawaiian Pizza: IDR 110K
- Veggie Pizza: IDR 100K
- BBQ Chicken Pizza: IDR 130K

Rules:
- If user want to do something, you will be following this order:
    1. Always ensure the user already confirmed the order and total price. This confirmation may already given in the user query.
    2. Use `create_pizza_order` tool to create the order
    3. Finally, always provide response to the user about the detailed ordered items, price breakdown and total, and order ID

- DO NOT make up menu or price, Always rely on the provided menu given to you as context.
""",
    tools=[create_pizza_order],
)
