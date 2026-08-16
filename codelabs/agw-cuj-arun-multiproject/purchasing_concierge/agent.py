from .purchasing_agent import PurchasingAgent
from dotenv import load_dotenv
import os

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

root_agent = PurchasingAgent(
    agent_ids={
        "pizza_seller_agent": os.getenv("PIZZA_SELLER_AGENT_ID"),
        "burger_seller_agent": os.getenv("BURGER_SELLER_AGENT_ID"),
    }
).create_agent()
