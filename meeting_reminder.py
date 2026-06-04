#!/usr/bin/python3
"""
macOS Meeting Reminder
Reads calendar events via AppleScript and shows a sliding dolphin banner
before each meeting.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from threading import Lock

DEFAULTS = {
    "poll_interval_seconds": 60,
    "reminder_minutes_before": 5,
    "banner_duration_seconds": 12,
    "only_meetings": True,
    "require_location": False,
    "title_keywords": [
        "会议", "Meeting", "meet", "评审", "Review", "1:1", "周会",
        "sync", "Standup", "stand-up", "面试", "讨论", "沟通", "对齐",
        "kickoff", "demo", "汇报", "晨会", "站会",
    ],
    "exclude_keywords": [
        "生日", "birthday", "纪念日", "假", "leave", "休假",
        "健身", "吃饭", "午餐", "晚餐", "提醒", "reminder",
    ],
    "calendar_names": [],
}


def _resolve_script_dir() -> Path:
    bundle_resources = os.environ.get("MEETING_REMINDER_RESOURCES")
    if bundle_resources:
        return Path(bundle_resources)
    return Path(__file__).resolve().parent


SCRIPT_DIR = _resolve_script_dir()
CONFIG_DIR = Path.home() / "Library/Application Support/MeetingReminder"
CONFIG_FILE = CONFIG_DIR / "config.json"
DEFAULT_CONFIG_FILE = SCRIPT_DIR / "config.default.json"
SHOWN_FILE = CONFIG_DIR / "shown_reminders.json"
BANNER_APP = SCRIPT_DIR / "MeetingBanner.app"
MSG_FILE = Path("/tmp/meeting-reminder-msg.txt")
BANNER_CONFIG_FILE = Path("/tmp/meeting-reminder-banner-config.json")
BANNER_LOG_FILE = Path("/tmp/meeting-reminder-banner.log")
MONITOR_LOG_FILE = Path("/tmp/meeting-reminder.log")
PID_FILE = Path("/tmp/meeting-reminder.pid")

_running = True


@dataclass
class CalendarEvent:
    title: str
    start: datetime
    uid: str
    location: str = ""
    calendar: str = ""


FIELD_SEP = "\x1f"
RECORD_SEP = "\n"


def log(msg: str) -> None:
    line = f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}"
    if sys.stderr.isatty():
        print(line, file=sys.stderr, flush=True)
    try:
        with MONITOR_LOG_FILE.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def load_config() -> dict:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        if DEFAULT_CONFIG_FILE.exists():
            CONFIG_FILE.write_text(
                DEFAULT_CONFIG_FILE.read_text(encoding="utf-8"), encoding="utf-8"
            )
            log(f"Created config: {CONFIG_FILE}")
        else:
            CONFIG_FILE.write_text(
                json.dumps(DEFAULTS, ensure_ascii=False, indent=2), encoding="utf-8"
            )

    try:
        data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        log(f"Config load failed ({exc}), using defaults")
        return dict(DEFAULTS)

    merged = dict(DEFAULTS)
    merged.update(data)
    return merged


def format_banner_text(
    event: CalendarEvent, config: dict, seconds_until_start: float
) -> str:
    title = event.title.strip() or "未命名会议"
    minutes = max(1, round(seconds_until_start / 60))
    location = event.location.strip()

    if location:
        if len(location) > 36:
            location = location[:33] + "..."
        return f"{title}\n📍 {location} · {minutes} 分钟后"

    return f"{title}\n{minutes} 分钟后开始"


class ReminderTracker:
    """Persistent dedup — each meeting only triggers once."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = Lock()
        self._shown: set[str] = self._load()

    def _load(self) -> set[str]:
        if not self._path.exists():
            return set()
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            return set(data) if isinstance(data, list) else set()
        except (OSError, json.JSONDecodeError):
            return set()

    def _save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        cutoff = time.time() - 86400
        self._shown = {
            key
            for key in self._shown
            if self._key_timestamp(key) >= cutoff
        }
        self._path.write_text(
            json.dumps(sorted(self._shown), ensure_ascii=False), encoding="utf-8"
        )

    @staticmethod
    def _key_timestamp(key: str) -> float:
        try:
            return float(key.rsplit("|", 1)[-1])
        except ValueError:
            return 0.0

    def should_show(self, event: CalendarEvent) -> bool:
        key = f"{event.uid}|{int(event.start.timestamp())}"
        with self._lock:
            if key in self._shown:
                return False
            self._shown.add(key)
            self._save()
            return True


def is_meeting(event: CalendarEvent, config: dict) -> bool:
    if not config.get("only_meetings", True):
        return True

    title_lower = event.title.lower()

    for kw in config.get("exclude_keywords", []):
        if kw.lower() in title_lower:
            return False

    allowed_cals = config.get("calendar_names") or []
    if allowed_cals and event.calendar not in allowed_cals:
        return False

    if config.get("require_location", False) and not event.location.strip():
        return False

    if event.location.strip():
        return True

    for kw in config.get("title_keywords", []):
        if kw.lower() in title_lower:
            return True

    return False


def should_trigger_now(
    seconds_until_start: float, seconds_until_reminder: float, config: dict
) -> bool:
    """Trigger at reminder time, or catch up if meeting was added late."""
    poll = config["poll_interval_seconds"]
    grace = 20
    remind_before = config["reminder_minutes_before"] * 60

    # Normal: around the configured reminder time (e.g. 5 min before)
    if -grace <= seconds_until_reminder <= poll:
        return True

    # Catch-up: meeting starts within reminder window but we missed normal trigger
    # (e.g. newly added meeting starting in 2 minutes)
    if 0 < seconds_until_start <= remind_before + poll:
        return True

    return False


def fetch_upcoming_events(hours_ahead: int = 24) -> list[CalendarEvent]:
    script = f"""
    set sep to ASCII character 31
    set output to {{}}
    set nowDate to current date
    set endDate to nowDate + ({hours_ahead} * hours)

    on pad2(n)
        if n < 10 then return "0" & n
        return n as text
    end pad2

    on isoFromDate(d)
        set y to year of d
        set m to my pad2(month of d as integer)
        set dy to my pad2(day of d)
        set h to my pad2(hours of d)
        set mn to my pad2(minutes of d)
        set s to my pad2(seconds of d)
        return (y as text) & "-" & m & "-" & dy & " " & h & ":" & mn & ":" & s
    end isoFromDate

    tell application "Calendar"
        repeat with cal in calendars
            set calName to name of cal
            set calEvents to (every event of cal whose start date >= nowDate and start date <= endDate)
            repeat with ev in calEvents
                set allDayFlag to false
                try
                    set allDayFlag to allday event of ev
                end try
                if allDayFlag is false then
                    set evTitle to summary of ev
                    set evLocation to location of ev
                    if evLocation is missing value then set evLocation to ""
                    set evStart to start date of ev
                    set end of output to evTitle & sep & (my isoFromDate(evStart)) & sep & (uid of ev as string) & sep & evLocation & sep & calName
                end if
            end repeat
        end repeat
    end tell

    set AppleScript's text item delimiters to linefeed
    return output as text
    """

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=60,
        )
    except subprocess.CalledProcessError as exc:
        log(f"Calendar read failed: {exc.stderr.strip() or exc}")
        return []
    except subprocess.TimeoutExpired:
        log("Calendar read timed out.")
        return []

    events: list[CalendarEvent] = []
    raw = result.stdout.strip()
    if not raw:
        return events

    for line in raw.split(RECORD_SEP):
        parts = line.split(FIELD_SEP)
        if len(parts) != 5:
            continue
        title, start_text, uid, location, calendar = parts
        try:
            start = datetime.strptime(start_text.strip(), "%Y-%m-%d %H:%M:%S")
        except ValueError:
            log(f"Skip event with bad time: {start_text!r} title={title!r}")
            continue
        events.append(
            CalendarEvent(
                title=title.strip() or "未命名会议",
                start=start,
                uid=uid.strip() or f"{title}-{start_text}",
                location=location.strip(),
                calendar=calendar.strip(),
            )
        )
    return events


def write_banner_config(config: dict) -> None:
    BANNER_CONFIG_FILE.write_text(
        json.dumps({"duration_seconds": config["banner_duration_seconds"]}),
        encoding="utf-8",
    )


def show_banner(text: str, config: dict, wait: bool = False) -> bool:
    if not BANNER_APP.exists():
        log(f"Missing {BANNER_APP.name}. Run: ./setup.sh")
        return False

    write_banner_config(config)
    MSG_FILE.write_text(text, encoding="utf-8")
    cmd = ["open", "-n", str(BANNER_APP)]
    if wait:
        cmd.insert(1, "-W")

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        log(f"Banner launch failed: {result.stderr.strip() or result.stdout.strip()}")
        return False
    return True


def check_meetings(tracker: ReminderTracker, config: dict) -> tuple[int, int, int]:
    now = datetime.now()
    target_seconds = config["reminder_minutes_before"] * 60
    events = fetch_upcoming_events()
    meetings = [e for e in events if is_meeting(e, config)]
    triggered = 0

    for event in meetings:
        seconds_until_start = (event.start - now).total_seconds()
        seconds_until_reminder = seconds_until_start - target_seconds

        if not should_trigger_now(seconds_until_start, seconds_until_reminder, config):
            continue
        if not tracker.should_show(event):
            continue

        time_text = event.start.strftime("%H:%M")
        banner_text = format_banner_text(event, config, seconds_until_start)
        if show_banner(banner_text, config):
            triggered += 1
            loc_info = f" @ {event.location}" if event.location.strip() else ""
            kind = "catch-up" if seconds_until_reminder < -20 else "normal"
            log(f"Reminder shown ({kind}): {event.title}{loc_info} at {time_text}")

    return len(events), len(meetings), triggered


def test_notification() -> None:
    subprocess.run(
        [
            "osascript",
            "-e",
            'display notification "通知测试成功" with title "Meeting Reminder"',
        ],
        check=False,
    )
    log("已发送系统通知测试（右上角）。")


def test_calendar_access() -> None:
    config = load_config()
    log("Reading calendar (this triggers Automation permission prompt)...")
    events = fetch_upcoming_events(hours_ahead=48)
    if not events:
        log("No upcoming events found, or calendar access denied.")
        return

    meetings = [e for e in events if is_meeting(e, config)]
    log(f"Found {len(events)} event(s), {len(meetings)} match meeting filter:")
    for event in events[:15]:
        loc = f" [{event.location}]" if event.location.strip() else ""
        tag = "✓" if is_meeting(event, config) else "·"
        log(f"  {tag} {event.start:%m-%d %H:%M} [{event.calendar}] {event.title}{loc}")


def open_config() -> None:
    load_config()
    subprocess.run(["open", str(CONFIG_FILE)], check=False)
    log(f"Opened config: {CONFIG_FILE}")


def run_monitor() -> None:
    global _running
    tracker = ReminderTracker(SHOWN_FILE)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    last_config_sig = ""

    while _running:
        config = load_config()
        sig = json.dumps(config, sort_keys=True)
        if sig != last_config_sig:
            log(
                f"Monitor running (pid={os.getpid()}, "
                f"poll={config['poll_interval_seconds']}s, "
                f"remind={config['reminder_minutes_before']}min, "
                f"banner={config['banner_duration_seconds']}s, "
                f"only_meetings={config['only_meetings']})"
            )
            last_config_sig = sig

        try:
            total, meetings, triggered = check_meetings(tracker, config)
            log(
                f"Poll OK: {total} event(s), {meetings} meeting(s), "
                f"{triggered} reminder(s) shown"
            )
        except Exception as exc:
            log(f"Poll error: {exc}")
            log(traceback.format_exc())

        poll = config["poll_interval_seconds"]
        for _ in range(poll):
            if not _running:
                break
            time.sleep(1)

    log("Monitor stopped.")


def _handle_signal(signum, _frame) -> None:
    global _running
    log(f"Received signal {signum}, shutting down...")
    _running = False


def main() -> None:
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    if "--test-notify" in sys.argv:
        test_notification()
        return

    if "--test-calendar" in sys.argv:
        test_calendar_access()
        return

    if "--test-banner" in sys.argv:
        config = load_config()
        log("Showing test banner...")
        show_banner("产品评审会\n📍 3楼会议室 A301 · 5 分钟后", config, wait=True)
        return

    if "--open-config" in sys.argv:
        open_config()
        return

    if "--scan-once" in sys.argv:
        config = load_config()
        tracker = ReminderTracker(SHOWN_FILE)
        total, meetings, triggered = check_meetings(tracker, config)
        log(f"Manual scan: {total} event(s), {meetings} meeting(s), {triggered} shown")
        return

    run_monitor()


if __name__ == "__main__":
    main()
