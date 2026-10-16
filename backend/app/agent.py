"""The expense assistant: a tool-use loop that works with several model providers.

The server sends the conversation and tool schemas to the model. When the model asks for a tool, the server
runs it as the signed-in user, sends the result back, and repeats until the model answers in text.

Providers (set LLM_PROVIDER, see config.py):
- groq / gemini / ollama / openai: any OpenAI-compatible chat-completions API (free options)
- anthropic: Claude via the Anthropic SDK (paid)
"""

import json
import time
from datetime import date

import requests
from flask import current_app

from . import services
from .models import User
from .tools import TOOL_SCHEMAS, execute_tool

MAX_TOOL_ROUNDS = 8

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

# Base URL, default model, and the config key holding the API key, per OpenAI-compatible provider.
PROVIDERS = {
    "groq": ("https://api.groq.com/openai/v1", "openai/gpt-oss-120b", "GROQ_API_KEY"),
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-flash-latest", "GEMINI_API_KEY"),
    "ollama": ("http://localhost:11434/v1", "qwen3:8b", None),
    "openai": ("", "", "LLM_API_KEY"),
}


class AgentError(RuntimeError):
    """The assistant isn't configured (missing key, unknown provider)."""


class AgentBusy(RuntimeError):
    """The model provider is rate-limiting us (common on free tiers)."""


def _tool_error(exc: Exception) -> str:
    return f"Error: {exc}"


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
        return _tool_error(exc), True


CURRENCY_SYMBOLS = {"INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}


def _system(user: User, today: date) -> str:
    symbol = CURRENCY_SYMBOLS.get(user.currency)
    example = f"{symbol}1,250" if symbol else f"{user.currency} 1,250"
    return SYSTEM_PROMPT.format(
        today=today.isoformat(), weekday=today.strftime("%A"), currency=user.currency, money_example=example
    )


GIVE_UP = "Sorry, that took too many steps. Could you try asking more simply?"


# ---------------------------------------------------------------- Anthropic (Claude)

def get_anthropic_client():
    import anthropic

    key = current_app.config["ANTHROPIC_API_KEY"]
    if not key:
        raise AgentError("ANTHROPIC_API_KEY is not configured")
    return anthropic.Anthropic(api_key=key, timeout=60, max_retries=2)


def _block_to_dict(block) -> dict:
    if block.type == "text":
        return {"type": "text", "text": block.text}
    if block.type == "tool_use":
        return {"type": "tool_use", "id": block.id, "name": block.name, "input": block.input}
    return {"type": block.type}


def _run_anthropic(messages: list[dict], user: User, client, today: date) -> dict:
    convo: list[dict] = [{"role": m["role"], "content": m["content"]} for m in messages]
    actions: list[dict] = []
    for _ in range(MAX_TOOL_ROUNDS):
        try:
            response = client.messages.create(
                model=current_app.config["LLM_MODEL"] or current_app.config["ANTHROPIC_MODEL"],
                max_tokens=1024,
                system=_system(user, today),
                tools=TOOL_SCHEMAS,
                messages=convo,
            )
        except Exception as exc:  # noqa: BLE001
            if exc.__class__.__name__ == "RateLimitError":
                raise AgentBusy(str(exc)) from exc
            raise
        if response.stop_reason != "tool_use":
            reply = "".join(b.text for b in response.content if b.type == "text").strip()
            return {"reply": reply or "Done.", "actions": actions}

        convo.append({"role": "assistant", "content": [_block_to_dict(b) for b in response.content]})
        results = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            content, is_error = _run_tool(block.name, block.input, user, today, actions)
            result = {"type": "tool_result", "tool_use_id": block.id, "content": content}
            if is_error:
                result["is_error"] = True
            results.append(result)
        convo.append({"role": "user", "content": results})
    return {"reply": GIVE_UP, "actions": actions}


# ---------------------------------------------------------------- OpenAI-compatible (Groq, Gemini, Ollama, ...)

OPENAI_TOOLS = [
    {
        "type": "function",
        "function": {"name": t["name"], "description": t["description"], "parameters": t["input_schema"]},
    }
    for t in TOOL_SCHEMAS
]


def _openai_settings() -> tuple[str, str, str]:
    cfg = current_app.config
    provider = cfg["LLM_PROVIDER"]
    if provider not in PROVIDERS:
        raise AgentError(f"Unknown LLM_PROVIDER '{provider}'")
    base, model, key_name = PROVIDERS[provider]
    base = (cfg["LLM_BASE_URL"] or base).rstrip("/")
    model = cfg["LLM_MODEL"] or model
    key = cfg["LLM_API_KEY"] or (cfg.get(key_name, "") if key_name else "")
    if provider == "ollama":
        key = key or "ollama"  # Ollama ignores the key but the header must be present
    if not base or not model:
        raise AgentError("Set LLM_BASE_URL and LLM_MODEL for the 'openai' provider")
    if not key:
        raise AgentError(f"{key_name or 'LLM_API_KEY'} is not configured")
    return base, model, key


RETRY_STATUSES = {429, 500, 502, 503, 504}  # rate limits and "model overloaded" are common on free tiers


def openai_post(url: str, payload: dict, key: str, retries: int = 2, sleep=time.sleep) -> dict:
    for attempt in range(retries + 1):
        resp = requests.post(url, json=payload, headers={"Authorization": f"Bearer {key}"}, timeout=60)
        if resp.status_code not in RETRY_STATUSES:
            break
        if attempt < retries:
            sleep(1.5 * (attempt + 1))
    if resp.status_code in RETRY_STATUSES:
        raise AgentBusy(f"{resp.status_code}: {resp.text[:300]}")
    if resp.status_code >= 400:
        raise RuntimeError(f"LLM API error {resp.status_code}: {resp.text[:500]}")
    return resp.json()


def _run_openai_compatible(messages: list[dict], user: User, today: date, post=None) -> dict:
    post = post or openai_post
    base, model, key = _openai_settings()
    convo: list[dict] = [{"role": "system", "content": _system(user, today)}]
    convo += [{"role": m["role"], "content": m["content"]} for m in messages]
    actions: list[dict] = []

    for _ in range(MAX_TOOL_ROUNDS):
        data = post(
            f"{base}/chat/completions",
            {"model": model, "messages": convo, "tools": OPENAI_TOOLS, "tool_choice": "auto",
             "temperature": 0.2, "max_tokens": 1024},
            key,
        )
        message = (data.get("choices") or [{}])[0].get("message") or {}
        tool_calls = message.get("tool_calls") or []
        if not tool_calls:
            reply = (message.get("content") or "").strip()
            return {"reply": reply or "Done.", "actions": actions}

        convo.append({"role": "assistant", "content": message.get("content") or "", "tool_calls": tool_calls})
        for call in tool_calls:
            fn = call.get("function") or {}
            raw = fn.get("arguments") or "{}"
            try:
                args = json.loads(raw) if isinstance(raw, str) else raw
            except json.JSONDecodeError:
                content = _tool_error("arguments were not valid JSON")
            else:
                content, _ = _run_tool(fn.get("name", ""), args, user, today, actions)
            convo.append({"role": "tool", "tool_call_id": call.get("id", ""), "content": content})
    return {"reply": GIVE_UP, "actions": actions}


# ---------------------------------------------------------------- entry point

def run_agent(messages: list[dict], user: User, client=None, today: date | None = None, post=None) -> dict:
    """messages: [{"role": "user"|"assistant", "content": str}, ...] ending with a user message.
    Returns {"reply": str, "actions": [...]}. Pass `client` (Anthropic-style) or `post` to fake the model in tests."""
    today = today or date.today()
    if client is not None or current_app.config["LLM_PROVIDER"] == "anthropic":
        return _run_anthropic(messages, user, client or get_anthropic_client(), today)
    return _run_openai_compatible(messages, user, today, post=post)
