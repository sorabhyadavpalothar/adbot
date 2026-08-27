import asyncio
import warnings

from telegram.warnings import PTBUserWarning

warnings.filterwarnings(
    "ignore",
    category=UserWarning,
    module=r"telegram\.ext\._conversationhandler",
)
warnings.filterwarnings(
    "ignore",
    message=r".*per_message.*",
    category=UserWarning,
)
warnings.filterwarnings(
    "ignore",
    category=PTBUserWarning,
)

from telegram import Update
from telegram.ext import (
    Application,
    ContextTypes,
)

from config.logger import LOG
from config.db import db, r

# ── Forwarding Engine ─────────────────────────
from engine.scheduler import ForwardingScheduler

# ── User handlers ─────────────────────────────
from handlers.users.add_user import (
    _edit_bubble as _user_edit_bubble,
    _cleanup as _user_cleanup,
    _KEY_MSG_ID,
)

# ── Models bootstrap ──────────────────────────
from models.config import bootstrap_config_table, check_user_permission
from models.users import bootstrap_users_table
from models.topics import bootstrap_topics_table
from models.forwarding_state import bootstrap_forwarding_state_table
from models.forwarding_schedule import bootstrap_forwarding_schedule_table

# ── Utilities / templates ─────────────────────
from utils.auto_delete import schedule_delete
from templates.messages import (
    WELCOME_MSG,
    CANCELLED_MSG,
)
from templates.inlinebutton import (
    WELCOME_KEYBOARD,
    CANCELLED_KEYBOARD_USER,
)


# ─────────────────────────────────────────────
#  /start
# ─────────────────────────────────────────────
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await check_user_permission(update):
        return
    user = update.effective_user
    schedule_delete(context, update.message.chat_id, update.message.message_id)
    sent = await update.message.reply_html(
        WELCOME_MSG(user),
        reply_markup=WELCOME_KEYBOARD(),
    )
    schedule_delete(context, sent.chat_id, sent.message_id)


# ─────────────────────────────────────────────
#  Global ❌ Cancel
# ─────────────────────────────────────────────
async def global_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer("Cancelled — no data saved.")
    if context.user_data.get(_KEY_MSG_ID):
        await _user_edit_bubble(context, CANCELLED_MSG, CANCELLED_KEYBOARD_USER())
        await _user_cleanup(context)


# ─────────────────────────────────────────────
#  Global error handler
# ─────────────────────────────────────────────
async def global_error_handler(
    update: object, context: ContextTypes.DEFAULT_TYPE
) -> None:
    """Log all exceptions and send a friendly alert to the user if possible."""
    import traceback
    from telegram import Update as TGUpdate

    err = context.error
    tb = "".join(traceback.format_exception(type(err), err, err.__traceback__))
    LOG.error("Unhandled exception:\n%s", tb)

    # Try to notify the user
    if isinstance(update, TGUpdate) and update.effective_message:
        try:
            await update.effective_message.reply_text(
                "⚠️ An internal error occurred. Please try again.",
            )
        except Exception:
            pass
    elif isinstance(update, TGUpdate) and update.callback_query:
        try:
            await update.callback_query.answer(
                "⚠️ An error occurred. Please try again.", show_alert=True
            )
        except Exception:
            pass


# ─────────────────────────────────────────────
#  Post-init: attach scheduler to bot_data
# ─────────────────────────────────────────────
async def _post_init(app: Application) -> None:
    scheduler: ForwardingScheduler = app.bot_data["scheduler"]
    task = asyncio.create_task(scheduler.run_forever(), name="forwarding-scheduler")
    app.bot_data["scheduler_task"] = task
    LOG.info("📅 Forwarding scheduler task launched")


# ─────────────────────────────────────────────
#  Pre-shutdown: stop scheduler + workers
# ─────────────────────────────────────────────
async def _pre_shutdown(app: Application) -> None:
    scheduler: ForwardingScheduler = app.bot_data.get("scheduler")
    if scheduler:
        await scheduler.stop_async()

    task: asyncio.Task | None = app.bot_data.get("scheduler_task")
    if task and not task.done():
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass
    LOG.info("📅 Scheduler task stopped cleanly")

    try:
        if db and not db.closed:
            db.close()
            LOG.info("PostgreSQL connection closed")
    except Exception as exc:
        LOG.error("Error closing DB: %s", exc)

    try:
        if r:
            r.close()
            LOG.info("Redis connection closed")
    except Exception as exc:
        LOG.error("Error closing Redis: %s", exc)


# ─────────────────────────────────────────────
#  Bot entry-point
# ─────────────────────────────────────────────
def main():
    # Bootstrap DB tables & schemas
    bootstrap_config_table()
    bootstrap_topics_table()  # must come before users (FK dependency)
    bootstrap_users_table()
    bootstrap_forwarding_state_table()
    bootstrap_forwarding_schedule_table()

    from engine.worker_bot import run_bot_worker

    run_bot_worker()


if __name__ == "__main__":
    main()
