"""Provider-agnostic tool-calling loop shared by the chat agent and the monthly coach.

The server sends the conversation, a system prompt and tool schemas to the model. When the model asks for a
tool, `executor(name, args)` runs it and returns the text sent back; the loop repeats until the model answers
in plain text.

Providers (set LLM_PROVIDER, see config.py):
- groq / gemini / ollama / openai: any OpenAI-compatible chat-completions API (free options)
- anthropic: Claude via the Anthropic SDK (paid)
"""

import json
import time
from collections.abc import Callable

import requests
from flask import current_app

MAX_TOOL_ROUNDS = 8

# Base URL, default model, and the config key holding the API key, per OpenAI-compatible provider.
PROVIDERS = {
    "groq": ("https://api.groq.com/openai/v1", "openai/gpt-oss-120b", "GROQ_API_KEY"),
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-flash-latest", "GEMINI_API_KEY"),
    "ollama": ("http://localhost:11434/v1", "qwen3:8b", None),
    "openai": ("", "", "LLM_API_KEY"),
}

RETRY_STATUSES = {429, 500, 502, 503, 504}  # rate limits and "model overloaded" are common on free tiers

# executor(name, args) -> (content for the model, is_error)
Executor = Callable[[str, object], tuple[str, bool]]


class AgentError(RuntimeError):
    """The model isn't configured (missing key, unknown provider)."""


class AgentBusy(RuntimeError):
    """The model provider is rate-limiting us (common on free tiers)."""


class TooManySteps(RuntimeError):
    """The model kept calling tools without giving a final answer."""


def tool_error(exc: Exception | str) -> str:
    return f"Error: {exc}"


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


def _loop_anthropic(messages, system, tools, executor, client, max_rounds, max_tokens) -> str:
    convo: list[dict] = [{"role": m["role"], "content": m["content"]} for m in messages]
    for _ in range(max_rounds):
        try:
            response = client.messages.create(
                model=current_app.config["LLM_MODEL"] or current_app.config["ANTHROPIC_MODEL"],
                max_tokens=max_tokens,
                system=system,
                tools=tools,
                messages=convo,
            )
        except Exception as exc:  # noqa: BLE001
            if exc.__class__.__name__ == "RateLimitError":
                raise AgentBusy(str(exc)) from exc
            raise
        if response.stop_reason != "tool_use":
            return "".join(b.text for b in response.content if b.type == "text").strip()

        convo.append({"role": "assistant", "content": [_block_to_dict(b) for b in response.content]})
        results = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            content, is_error = executor(block.name, block.input)
            result = {"type": "tool_result", "tool_use_id": block.id, "content": content}
            if is_error:
                result["is_error"] = True
            results.append(result)
        convo.append({"role": "user", "content": results})
    raise TooManySteps()


# ---------------------------------------------------------------- OpenAI-compatible (Groq, Gemini, Ollama, ...)

def to_openai_tools(tools: list[dict]) -> list[dict]:
    return [
        {"type": "function",
         "function": {"name": t["name"], "description": t["description"], "parameters": t["input_schema"]}}
        for t in tools
    ]


def openai_settings() -> tuple[str, str, str]:
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


def _loop_openai(messages, system, tools, executor, post, max_rounds, max_tokens) -> str:
    base, model, key = openai_settings()
    convo: list[dict] = [{"role": "system", "content": system}]
    convo += [{"role": m["role"], "content": m["content"]} for m in messages]
    openai_tools = to_openai_tools(tools)

    for _ in range(max_rounds):
        data = post(
            f"{base}/chat/completions",
            {"model": model, "messages": convo, "tools": openai_tools, "tool_choice": "auto",
             "temperature": 0.2, "max_tokens": max_tokens},
            key,
        )
        message = (data.get("choices") or [{}])[0].get("message") or {}
        tool_calls = message.get("tool_calls") or []
        if not tool_calls:
            return (message.get("content") or "").strip()

        convo.append({"role": "assistant", "content": message.get("content") or "", "tool_calls": tool_calls})
        for call in tool_calls:
            fn = call.get("function") or {}
            raw = fn.get("arguments") or "{}"
            try:
                args = json.loads(raw) if isinstance(raw, str) else raw
            except json.JSONDecodeError:
                content = tool_error("arguments were not valid JSON")
            else:
                content, _ = executor(fn.get("name", ""), args)
            convo.append({"role": "tool", "tool_call_id": call.get("id", ""), "content": content})
    raise TooManySteps()


# ---------------------------------------------------------------- entry point

def run_tool_loop(
    messages: list[dict],
    system: str,
    tools: list[dict],
    executor: Executor,
    *,
    client=None,
    post=None,
    max_rounds: int = MAX_TOOL_ROUNDS,
    max_tokens: int = 1024,
) -> str:
    """Run the model with tools until it answers in text; returns that text.

    `tools` use the Anthropic schema shape ({name, description, input_schema}); they are converted for
    OpenAI-compatible providers. Pass `client` (Anthropic-style) or `post` to fake the model in tests.
    Raises AgentError, AgentBusy or TooManySteps."""
    if client is not None or current_app.config["LLM_PROVIDER"] == "anthropic":
        return _loop_anthropic(messages, system, tools, executor, client or get_anthropic_client(),
                               max_rounds, max_tokens)
    return _loop_openai(messages, system, tools, executor, post or openai_post, max_rounds, max_tokens)
