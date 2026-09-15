from google.adk.agents import Agent

root_agent = Agent(
    name="hello_world_agent",
    model="gemini-2.5-flash",
    description="A minimal hello world agent that greets users.",
    instruction="You are a friendly assistant. Greet the user warmly and respond helpfully to any message.",
)
