#!/usr/bin/python3 -IS
# Island Notch: Claude Code hook for the live session in the notch.
#
# Register it in ~/.claude/settings.json for SessionStart, UserPromptSubmit,
# PreToolUse, PostToolUse, Notification, Stop, SubagentStop and SessionEnd
# (see the README). Claude Code passes each event as JSON on stdin.
#
# It keeps one small file per session in $XDG_RUNTIME_DIR/island-notch/claude/
# (folder 0700, files 0600, written to a temporary file and renamed): the state
# (working, waiting for you, done), the last few steps as tool + short target
# (a file name, a command cut to 40 characters, a pattern), the session title,
# the project folder and what is needed to focus its terminal (process id,
# tmux pane). Never prompts, tool output, file contents or transcript text.
#
# A notifier hook of your own may leave "<session>.notif" next to it with the
# id of a desktop notification ({"id": 17, "at": <ms>}), such as "needs your
# permission": once the session moves on (a tool finished, a new prompt, the
# turn or the session ended) that notification is closed (as its sender, over
# D-Bus) and dropped from the notch and from Glass Notifications' history.
#
# Always exits 0 at once and prints nothing, so it never changes what Claude does.

import json
import os
import sys
import time

RUN = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
DIR = os.path.join(RUN, "island-notch", "claude")
MAX_STEPS = 4
SHELLS = {"sh", "bash", "dash", "zsh", "fish", "env", "timeout"}


def now_ms():
    return int(time.time() * 1000)


def cut(text, n):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def base(path):
    return os.path.basename(str(path or "").rstrip("/")) or str(path or "")


def step_of(tool, inp):
    """Tool name and a short target; the notch turns the tool into a verb."""
    inp = inp if isinstance(inp, dict) else {}
    if tool in ("Edit", "MultiEdit", "Write", "Read"):
        return base(inp.get("file_path"))
    if tool == "NotebookEdit":
        return base(inp.get("notebook_path"))
    if tool == "Bash":
        cmd = str(inp.get("command") or "").strip().split("\n")[0]
        # "cd <somewhere> && make" says "make"
        while cmd.startswith("cd ") and "&&" in cmd:
            cmd = cmd.split("&&", 1)[1].strip()
        return cut(cmd, 40)
    if tool in ("Grep", "Glob"):
        return cut(inp.get("pattern"), 40)
    if tool in ("Task", "Agent"):
        return cut(inp.get("description") or inp.get("subagent_type"), 40)
    if tool == "WebFetch":
        url = str(inp.get("url") or "")
        return url.split("//", 1)[-1].split("/", 1)[0][:40]
    if tool == "WebSearch":
        return cut(inp.get("query"), 40)
    if tool == "Skill":
        return cut(inp.get("skill") or inp.get("command"), 40)
    return ""


def tool_name(tool):
    tool = str(tool or "")
    if tool.startswith("mcp__"):
        return tool.split("__")[-1]
    return tool


def find_title(transcript):
    """Your /rename, else Claude's own title (same as claude-notch-notify)."""
    try:
        import mmap
        with open(transcript, "rb") as f:
            if os.fstat(f.fileno()).st_size == 0:
                return ""
            with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
                for marker, key in ((b'"type":"custom-title"', "customTitle"), (b'"type":"ai-title"', "aiTitle")):
                    at = m.rfind(marker)
                    if at < 0:
                        continue
                    start = m.rfind(b"\n", 0, at) + 1
                    end = m.find(b"\n", at)
                    line = m[start: end if end >= 0 else len(m)]
                    title = json.loads(line.decode("utf-8", "replace")).get(key) or ""
                    if title:
                        return cut(title, 80)
    except Exception:
        pass
    return ""


def proc_stat(pid):
    with open("/proc/%d/stat" % pid, "rb") as f:
        raw = f.read().decode("utf-8", "replace")
    comm = raw[raw.index("(") + 1: raw.rindex(")")]
    ppid = int(raw[raw.rindex(")") + 2:].split()[1])
    return comm, ppid


def claude_pid():
    """The Claude Code process: the first ancestor that is not a shell."""
    pid = os.getppid()
    for _ in range(5):
        try:
            comm, ppid = proc_stat(pid)
        except Exception:
            return 0
        if comm not in SHELLS:
            return pid
        pid = ppid
    return 0


def write_private(path, data):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def retire_notice(sid):
    """Close the desktop notification a notifier left for this session."""
    path = os.path.join(DIR, sid + ".notif")
    try:
        with open(path) as f:
            rec = json.load(f)
        os.unlink(path)
        nid = int(rec.get("id") or 0)
        at = int(rec.get("at") or 0)
    except Exception:
        return
    if nid <= 0:
        return
    # Glass Notifications files each one as history/<timestamp>-<id>.json;
    # ids start over with the shell, so only a Claude one sent since then.
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    hist = os.path.join(state, "omarchy", "notifications", "history")
    imgs = os.path.join(state, "omarchy", "notifications", "images")
    try:
        suffix = "-%d.json" % nid
        for name in os.listdir(hist):
            if not name.endswith(suffix):
                continue
            stem = name[: -len(".json")]
            try:
                if int(stem.split("-", 1)[0]) < at - 10000:
                    continue
                with open(os.path.join(hist, name), "rb") as f:
                    if b'"app":"Claude"' not in f.read(65536):
                        continue
                os.unlink(os.path.join(hist, name))
                for img in os.listdir(imgs):
                    if img.startswith(stem + "-"):
                        os.unlink(os.path.join(imgs, img))
            except Exception:
                pass
    except Exception:
        pass
    # The live notification (sender's close) and the notch, without waiting.
    import subprocess
    script = (
        'gdbus call --session --dest org.freedesktop.Notifications '
        '--object-path /org/freedesktop/Notifications '
        '--method org.freedesktop.Notifications.CloseNotification "$1"; '
        'omarchy-shell -q io.github.hugorolimf.island retract "$1"'
    )
    try:
        subprocess.Popen(["sh", "-c", script, "sh", str(nid)], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception:
        pass


def main():
    ev = json.loads(sys.stdin.read() or "{}")
    event = str(ev.get("hook_event_name") or "")
    sid = "".join(c for c in str(ev.get("session_id") or "") if c.isalnum() or c == "-")[:64]
    if not sid or not event:
        return
    # Claude Code's own helpers (the suggestion after each turn) end with an
    # empty agent_type and never start: nothing to show.
    if event == "SubagentStop" and not ev.get("agent_type"):
        return

    old = os.umask(0o077)
    try:
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        for d in (os.path.dirname(DIR), DIR):
            if os.stat(d).st_mode & 0o077:
                os.chmod(d, 0o700)
    finally:
        os.umask(old)

    path = os.path.join(DIR, sid + ".json")
    if event in ("PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd"):
        retire_notice(sid)
    if event == "SessionEnd":
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        return

    import fcntl
    lock = os.open(os.path.join(DIR, ".lock"), os.O_WRONLY | os.O_CREAT, 0o600)
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        try:
            with open(path) as f:
                s = json.load(f)
        except Exception:
            s = {}
        t = now_ms()
        cwd = str(ev.get("cwd") or s.get("cwd") or "")
        project = base(cwd) or "Claude"
        s.setdefault("state", "idle")
        s.setdefault("steps", [])
        s.setdefault("started", t)
        s["v"] = 1
        s["id"] = sid
        s["cwd"] = cwd
        s["project"] = project
        transcript = str(ev.get("transcript_path") or "")
        if event in ("SessionStart", "UserPromptSubmit", "Stop") or not s.get("title"):
            s["title"] = find_title(transcript) if transcript else ""
        if event == "SessionStart" or not s.get("pid"):
            s["pid"] = claude_pid()
            s["tmuxPane"] = os.environ.get("TMUX_PANE", "") if os.environ.get("TMUX") else ""
            s["tmuxSocket"] = os.environ.get("TMUX", "").split(",")[0] if s["tmuxPane"] else ""
            if transcript:
                s["transcript"] = transcript

        changed = True
        if event == "SessionStart":
            if ev.get("source") in ("startup", "clear"):
                s["state"] = "idle"
                s["steps"] = []
        elif event == "UserPromptSubmit":
            s["state"] = "working"
            s["turnAt"] = t
            s["tools"] = 0
            s["steps"] = []
        elif event == "PreToolUse":
            tool = tool_name(ev.get("tool_name"))
            step = {"tool": tool, "target": step_of(tool, ev.get("tool_input")), "at": t}
            s["steps"] = (s["steps"] + [step])[-MAX_STEPS:]
            s["tools"] = int(s.get("tools") or 0) + 1
            # a question for you, or a plan to approve
            s["state"] = "waiting" if tool in ("AskUserQuestion", "ExitPlanMode") else "working"
            if s.get("state") == "working" and not s.get("turnAt"):
                s["turnAt"] = t
        elif event == "PostToolUse":
            s["state"] = "working"
        elif event == "Notification":
            kind = str(ev.get("notification_type") or "")
            msg = str(ev.get("message") or "")
            if kind == "permission_prompt" or (not kind and "permission" in msg):
                s["state"] = "waiting"
            else:
                changed = False  # "waiting for your input" after a turn: not news
        elif event == "SubagentStop":
            step = {"tool": "_subagentDone", "target": cut(ev.get("agent_type"), 40), "at": t}
            s["steps"] = (s["steps"] + [step])[-MAX_STEPS:]
        elif event == "Stop":
            # Only a turn that was under way ends as "done"; a Stop with
            # nothing before it (a repeat, an empty turn) changes nothing.
            if s.get("state") in ("working", "waiting"):
                s["state"] = "done"
                s["doneAt"] = t
            else:
                changed = False
        else:
            changed = False
        if changed:
            s["updated"] = t
            write_private(path, s)
    finally:
        os.close(lock)


if __name__ == "__main__":
    try:
        # `claude-hook.py --retire <session>`: for a notifier that finds the
        # session already moved on by the time its notification is up.
        if len(sys.argv) == 3 and sys.argv[1] == "--retire":
            retire_notice("".join(c for c in sys.argv[2] if c.isalnum() or c == "-")[:64])
        else:
            main()
    except Exception:
        pass
    sys.exit(0)
