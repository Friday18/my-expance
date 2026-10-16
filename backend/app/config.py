import os


def _database_url() -> str:
    url = os.getenv("DATABASE_URL", "sqlite:///myexpance.db")
    # Render and Heroku hand out postgres:// URLs; SQLAlchemy wants an explicit driver.
    if url.startswith("postgres://"):
        url = "postgresql+psycopg://" + url[len("postgres://"):]
    elif url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


class Config:
    SQLALCHEMY_DATABASE_URI = _database_url()
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True}
    MAX_CONTENT_LENGTH = 64 * 1024

    AUTH_MODE = os.getenv("AUTH_MODE", "firebase")  # "firebase" or "dev"
    FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "")

    # Which model runs the assistant:
    #   groq      - free tier, no card needed (default)   key: GROQ_API_KEY
    #   gemini    - Google AI Studio free tier            key: GEMINI_API_KEY
    #   ollama    - runs on your own computer, free        no key
    #   anthropic - Claude, paid                           key: ANTHROPIC_API_KEY
    #   openai    - any other OpenAI-compatible API        LLM_BASE_URL + LLM_API_KEY
    LLM_PROVIDER = os.getenv("LLM_PROVIDER", "groq").strip().lower()
    LLM_MODEL = os.getenv("LLM_MODEL", "")  # empty = the provider's default below
    LLM_BASE_URL = os.getenv("LLM_BASE_URL", "")
    LLM_API_KEY = os.getenv("LLM_API_KEY", "")
    GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
    ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
    ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-haiku-5-5")
    CHAT_DAILY_LIMIT = int(os.getenv("CHAT_DAILY_LIMIT", "60"))
    CHAT_MAX_MESSAGES = 40
    CHAT_MAX_CHARS = 2000

    RATELIMIT_DEFAULT = os.getenv("RATELIMIT_DEFAULT", "120 per minute")
    RATELIMIT_STORAGE_URI = os.getenv("RATELIMIT_STORAGE_URI", "memory://")
    RATELIMIT_HEADERS_ENABLED = True

    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")

    APP_NAME = "My Expance"
    SUPPORT_EMAIL = os.getenv("SUPPORT_EMAIL", "support@example.com")
    DEVELOPER_NAME = os.getenv("DEVELOPER_NAME", "My Expance")
    SENTRY_DSN = os.getenv("SENTRY_DSN", "")
