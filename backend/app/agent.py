"""The expense assistant: logs and edits expenses and answers spending questions with 7 narrow tools.

The tool loop itself lives in llm.py and is shared with the monthly coach (coach.py)."""

import json
from datetime import date

import requests  # noqa: F401  (re-exported: tests patch agent.requests.post)

from . import services
from .llm import (  # noqa: F401  (re-exported for routes and tests)
    PROVIDERS,
    RETRY_STATUSES,
    AgentBusy,
    AgentError,
    TooManySteps,
    openai_post,
    run_tool_loop,
    tool_error,
)
from .models import User
from .tools import TOOL_SCHEMAS, execute_tool

SYSTEM_PROMPT = """You are the assistant inside My Expance, a personal expense tracker.
Today is {today} ({weekday}). The user's currency is {currency}.

What you do:
- Log expenses from plain sentences ("spent 450 on lunch", "uber 220 yesterday") with add_expense.
  Pick the closest category. Keep notes short. Log several items if the user lists several.
- Edit or delete expenses when asked. Find the right one with list_expenses first. If more than one
  could match, ask which one instead of guessing.
- Answer questions about spending with spending_summary, list_expenses or budget_status.
  Never invent numbers: every figure you state must come from a tool result.

Style: short and friendly, one to three sentences. Format money like {money_example}.
If the message is not about money or expenses, say briefly what you can help with."""

CURRENCY_SYMBOLS = {"INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}

GIVE_UP = "Sorry, that took too many steps. Could you try asking more simply?"


def money_example(currency: str) -> str:
    symbol = CURRENCY_SYMBOLS.get(currency)
    return f"{symbol}1,250" if symbol else f"{currency} 1,250"


def _system(user: User, today: date) -> str:
    return SYSTEM_PROMPT.format(
        today=today.isoformat(), weekday=today.strftime("%A"), currency=user.currency,
        money_example=money_example(user.currency),
    )


def _run_tool(name: str, args, user: User, today: date, actions: list) -> tuple[str, bool]:
    """Run one tool call. Returns (content for the model, is_error)."""
    try:
        if not isinstance(args, dict):
            raise services.ValidationError("tool arguments must be an object")
        result, action = execute_tool(name, args, user, today=today)
        if action:
            actions.append(action)
        return json.dumps(result), False
    except (services.ValidationError, services.NotFound, KeyError, TypeError, ValueError) as exc:
        return tool_error(exc), True


def run_agent(messages: list[dict], user: User, client=None, today: date | None = None, post=None) -> dict:
    """messages: [{"role": "user"|"assistant", "content": str}, ...] ending with a user message.
    Returns {"reply": str, "actions": [...]}. Pass `client` (Anthropic-style) or `post` to fake the model in tests."""
    today = today or date.today()
    actions: list[dict] = []
    try:
        reply = run_tool_loop(
            messages,
            _system(user, today),
            TOOL_SCHEMAS,
            lambda name, args: _run_tool(name, args, user, today, actions),
            client=client,
            post=post,
        )
    except TooManySteps:
        return {"reply": GIVE_UP, "actions": actions}
    return {"reply": reply or "Done.", "actions": actions}
