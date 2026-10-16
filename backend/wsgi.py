import os

from dotenv import load_dotenv

load_dotenv(override=True)  # .env wins, so edits apply on reload

from app import create_app  # noqa: E402

app = create_app()

if __name__ == "__main__":
    # extra_files: restart automatically when .env changes
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5001")), debug=True, extra_files=[".env"])
