import asyncio
import os
import sys

from dotenv import load_dotenv

sys.path.insert(0, os.getcwd())
load_dotenv(".env")

from config import GROQ_MODEL, TELEGRAM_BOT_TOKEN  # noqa: E402
from database import reload_products  # noqa: E402
from sales_agent import SalesAgent  # noqa: E402
from telegram import Bot  # noqa: E402


async def main() -> None:
    bot = Bot(TELEGRAM_BOT_TOKEN)
    me = await bot.get_me()
    if not me.username:
        raise RuntimeError("Telegram getMe returned no username")

    agent = SalesAgent()
    completion = await agent._client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[{"role": "user", "content": "Reply with OK."}],
        max_tokens=3,
    )
    if not completion.choices:
        raise RuntimeError("Groq returned no choices")

    print("telegram_get_me=ok")
    print("groq_completion=ok")
    print(f"products={len(reload_products())}")


asyncio.run(main())
