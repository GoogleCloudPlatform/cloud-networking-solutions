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

from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.tasks import TaskUpdater
from a2a.types import (
    Part,
    TaskState,
    TextPart,
)
from a2a.utils import new_agent_text_message, new_task
from google.adk.artifacts import InMemoryArtifactService
from google.adk.memory.in_memory_memory_service import InMemoryMemoryService
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types


class ADKAgentExecutor(AgentExecutor):
    def __init__(
        self,
        agent,
        status_message='Processing burger order...',
        artifact_name='response',
    ):
        self.agent = agent
        self.status_message = status_message
        self.artifact_name = artifact_name
        self.runner = Runner(
            app_name=agent.name,
            agent=agent,
            artifact_service=InMemoryArtifactService(),
            session_service=InMemorySessionService(),
            memory_service=InMemoryMemoryService(),
        )

    async def cancel(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        raise NotImplementedError('Cancellation is not implemented for ADKAgentExecutor.')

    async def execute(
        self,
        context: RequestContext,
        event_queue: EventQueue,
    ) -> None:
        if not context.message:
            raise ValueError('Message should be present in request context')

        query = context.get_user_input()
        task = context.current_task or new_task(context.message)
        await event_queue.enqueue_event(task)

        updater = TaskUpdater(event_queue, task.id, task.context_id)
        if context.call_context and hasattr(context.call_context, "user") and context.call_context.user:
            user_id = context.call_context.user.user_name
        else:
            user_id = 'gemini_enterprise_user'

        try:
            await updater.update_status(
                TaskState.working,
                new_agent_text_message(
                    self.status_message, task.context_id, task.id
                ),
            )

            session = await self.runner.session_service.get_session(
                app_name=self.agent.name,
                user_id=user_id,
                session_id=task.context_id,
            )
            if not session:
                session = await self.runner.session_service.create_session(
                    app_name=self.agent.name,
                    user_id=user_id,
                    state={},
                    session_id=task.context_id,
                )

            content = types.Content(
                role='user', parts=[types.Part.from_text(text=query)]
            )

            response_text = ''
            async for event in self.runner.run_async(
                user_id=user_id, session_id=session.id, new_message=content
            ):
                if (
                    event.is_final_response()
                    and event.content
                    and event.content.parts
                ):
                    for part in event.content.parts:
                        if hasattr(part, 'text') and part.text:
                            response_text += part.text + '\n'

            if not response_text:
                response_text = "Task completed."

            await updater.add_artifact(
                [Part(root=TextPart(text=response_text))],
                name=self.artifact_name,
            )
            await updater.complete()

        except Exception as e:
            await updater.update_status(
                TaskState.failed,
                new_agent_text_message(
                    f'Error: {e!s}', task.context_id, task.id
                ),
                final=True,
            )
