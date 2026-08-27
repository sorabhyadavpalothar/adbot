# ─────────────────────────────────────────────
#  engine / worker_bot.py
#
#  Bot Worker Manager & Application Lifecycle Coordinator.
#
#  Manages the Telegram Bot Application instance,
#  registers all handlers, post_init / shutdown hooks,
#  and coordinates with ForwardingScheduler.
# ─────────────────────────────────────────────

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
    ApplicationBuilder,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)

from config.logger import LOG
from config.db import BOT_TOKEN, r

# ── Forwarding Engine Scheduler ────────────────
from engine.scheduler import ForwardingScheduler

# ── User handlers ─────────────────────────────
from handlers.users.add_user import (
    build_add_user_conv,
    _edit_bubble as _user_edit_bubble,
    _cleanup as _user_cleanup,
    _KEY_MSG_ID,
)
from handlers.users.view_user import (
    VIEW_USERS_HANDLERS,
    build_user_edit_delay_conv,
    build_user_edit_source_conv,
    build_user_edit_channel_conv,
)

# ── Topic handlers ────────────────────────────
from handlers.topics.add_topic import build_add_topic_conv
from handlers.topics.view_topic import VIEW_TOPIC_HANDLERS, build_view_topic_conv

# ── Settings handlers ─────────────────────────
from handlers.settings.manage_settings import (
    SETTINGS_HANDLERS,
    build_manage_settings_conv,
)

from models.config import check_user_permission
from utils.auto_delete import schedule_delete
from templates.messages import (
    WELCOME_MSG,
    CANCELLED_MSG,
)
from templates.inlinebutton import (
    WELCOME_KEYBOARD,
    CANCELLED_KEYBOARD_USER,
)


class BotWorkerManager:
    """
    BotWorkerManager handles the Telegram Bot UI Application,
    registers command/callback handlers, and launches the ForwardingScheduler.
    """

    def __init__(self):
        self.app = None
        self.scheduler = None

    async def start(self) -> None:
        """Initialize and run the bot application."""
        self.app = (
            ApplicationBuilder()
            .token(BOT_TOKEN)
            .post_init(self._post_init)
            .post_shutdown(self._pre_shutdown)
            .build()
        )

        # Attach scheduler to bot_data
        self.scheduler = ForwardingScheduler(redis_client=r)
        self.app.bot_data["scheduler"] = self.scheduler

        # Register handlers
        self._register_handlers()

        LOG.info("🤖 BotWorkerManager starting polling...")
        await self.app.initialize()
        await self.app.start()
        await self.app.updater.start_polling(drop_pending_updates=True)

    async def _post_init(self, app: Application) -> None:
        scheduler: ForwardingScheduler = app.bot_data["scheduler"]
        task = asyncio.create_task(scheduler.run_forever(), name="forwarding-scheduler")
        app.bot_data["scheduler_task"] = task
        LOG.info("📅 Forwarding scheduler task launched")

    async def _pre_shutdown(self, app: Application) -> None:
        LOG.info("🛑 Bot shutting down...")
        scheduler: ForwardingScheduler = app.bot_data.get("scheduler")
        if scheduler:
            await scheduler.stop_async()
        st_task = app.bot_data.get("scheduler_task")
        if st_task and not st_task.done():
            st_task.cancel()
            try:
                await st_task
            except asyncio.CancelledError:
                pass
        LOG.info("👋 Bot shutdown complete.")

    def _register_handlers(self) -> None:
        app = self.app

        async def start_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
            if not await check_user_permission(update):
                return
            user = update.effective_user
            schedule_delete(context, update.message.chat_id, update.message.message_id)
            sent = await update.message.reply_html(
                WELCOME_MSG(user),
                reply_markup=WELCOME_KEYBOARD(user.id if user else 0),
            )
            context.user_data[_KEY_MSG_ID] = sent.message_id
            context.user_data["au_chat_id"] = sent.chat_id
            schedule_delete(context, sent.chat_id, sent.message_id)

        async def global_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
            query = update.callback_query
            await query.answer("Cancelled — no data saved.")
            if context.user_data.get(_KEY_MSG_ID):
                await _user_edit_bubble(
                    context, CANCELLED_MSG, CANCELLED_KEYBOARD_USER()
                )
                await _user_cleanup(context)

        async def global_error_handler(
            update: object, context: ContextTypes.DEFAULT_TYPE
        ) -> None:
            import traceback
            from telegram import Update as TGUpdate
            from telegram.error import NetworkError, BadRequest

            err = context.error
            err_str = str(err)

            # Suppress message edit errors silently
            if "is not modified" in err_str or "There is no text in the message to edit" in err_str:
                return

            # Handle NetworkError / Internet disconnect cleanly without huge traceback log
            if (isinstance(err, NetworkError) and not isinstance(err, BadRequest)) or "getaddrinfo failed" in err_str or "ConnectError" in err_str:
                LOG.warning("🌐 Network Connection Error (Internet Disconnected): %s", err)
                if isinstance(update, TGUpdate) and update.callback_query:
                    try:
                        await update.callback_query.answer(
                            "🌐 Internet connection error. Please check your network and try again.",
                            show_alert=True,
                        )
                    except Exception:
                        pass
                return

            tb = "".join(traceback.format_exception(type(err), err, err.__traceback__))
            LOG.error("Unhandled exception:\n%s", tb)

            # For callback queries: answer the query with an alert
            if isinstance(update, TGUpdate) and update.callback_query:
                try:
                    await update.callback_query.answer(
                        "⚠️ An error occurred. Please tap the button again.",
                        show_alert=True,
                    )
                except Exception:
                    pass
            # For regular messages: reply with error text
            elif isinstance(update, TGUpdate) and update.message:
                try:
                    await update.message.reply_text(
                        "⚠️ An internal error occurred. Please try again."
                    )
                except Exception:
                    pass

        async def cb_global_noop(update: Update, context: ContextTypes.DEFAULT_TYPE):
            query = update.callback_query
            if query:
                try:
                    await query.answer()
                except Exception:
                    pass

        # Handlers
        app.add_handler(CommandHandler("start", start_cmd), group=0)
        app.add_handler(
            CallbackQueryHandler(cb_global_noop, pattern=r"^noop(:.*)?$"), group=0
        )
        app.add_error_handler(global_error_handler)

        app.add_handler(build_add_user_conv(), group=1)
        app.add_handler(build_user_edit_delay_conv(), group=1)
        app.add_handler(build_user_edit_source_conv(), group=1)
        app.add_handler(build_user_edit_channel_conv(), group=1)

        app.add_handler(build_add_topic_conv(), group=1)
        app.add_handler(build_view_topic_conv(), group=1)

        app.add_handler(build_manage_settings_conv(), group=1)

        for h in (
            VIEW_USERS_HANDLERS
            + VIEW_TOPIC_HANDLERS
            + SETTINGS_HANDLERS
        ):
            app.add_handler(h, group=2)


def run_bot_worker() -> None:
    """Helper entry point to initialize application and run bot workers."""
    bot_manager = BotWorkerManager()

    app = (
        ApplicationBuilder()
        .token(BOT_TOKEN)
        .post_init(bot_manager._post_init)
        .post_shutdown(bot_manager._pre_shutdown)
        .build()
    )

    scheduler = ForwardingScheduler(redis_client=r)
    app.bot_data["scheduler"] = scheduler
    bot_manager.app = app
    bot_manager._register_handlers()

    print("🤖 Bot started successfully")
    app.run_polling(drop_pending_updates=True)
