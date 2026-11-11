import asyncio
import json
from pathlib import Path

from dotenv import dotenv_values
from telegram import Bot


async def main() -> None:
    app_dir = Path("/opt/tg-max-bridge")
    config = dotenv_values(app_dir / ".env")
    token = config.get("BOT_TOKEN")
    if not token:
        raise RuntimeError("BOT_TOKEN is missing")

    me = await Bot(token).get_me()
    if not me.username:
        raise RuntimeError("Telegram getMe returned no username")

    with (app_dir / "max_session.json").open(encoding="utf-8") as handle:
        session = json.load(handle)
    if not isinstance(session, dict):
        raise RuntimeError("MAX session is not a JSON object")

    print("telegram_get_me=ok")
    print("max_session_json=valid")


asyncio.run(main())
