#!/usr/bin/env python3
"""Log parser for llm-router service.

A lightweight class that can be fed log lines continuously (no journalctl
calls inside the class).  It extracts model info, active tasks and checkpoint
state similar to the previous version.

Example
    parser = LogParser()
    for line in logs:                # any source of lines
        parser.feed_line(line)
    state = parser.state()
"""

import re
from typing import List, Dict, Any
from dataclasses import dataclass

# Regular expressions for the fields we care about
_RE_MODEL = re.compile(r"srv\s+load_model:\s+loading model '(.+)'", re.I)
_RE_MODEL_ARGS = re.compile(
    r"srv\s+load:\s+spawning server instance with name='([^']+)' on port (\d+)", re.I
)
_RE_TASK = re.compile(
    r"srv\s+slot\s+launch_slot_:\s+id\s+(\d+)\s+task\s+([^ ]+)\s+processing task, is_child = 0",
    re.I,
)
_RE_NPAST = re.compile(
    r"slot\s+update_slots:\s+id\s+\d+\s+task\s+\d+\s+n_past = (\d+)", re.I
)
_RE_POS_MIN = re.compile(
    r"slot\s+update_slots:\s+id\s+\d+\s+task\s+\d+\s+pos_min = (\d+)", re.I
)
_RE_CHECKPOINT = re.compile(
    r"slot\s+update_slots:\s+id\s+\d+\s+task\s+\d+\s+created context checkpoint\s+(\d+)\s+of\s+(\d+)\s+\(pos_min = (\d+),\s*pos_max = (\d+),\s*n_tokens=\*\*\*size = ([0-9.]+)\)",
    re.I,
)
_RE_EVAL = re.compile(
    r"slot\s+print_timing:\s+id\s+(\d+)\s+task\s+(\d+)\s+prompt eval time = .* n_tokens=([0-9]+)\s+batch\.n_tokens=([0-9]+)",
    re.I,
)

# Systemd service lifecycle patterns
_RE_SYSTEMD_STARTING = re.compile(r"systemd\[1\]:\s*Starting\s+(.+?)\.\.\.", re.I)
_RE_SYSTEMD_STARTED = re.compile(r"systemd\[1\]:\s*Started\s+(.+?)\.", re.I)
_RE_SYSTEMD_STOPPING = re.compile(r"systemd\[1\]:\s*Stopping\s+(.+?)\.\.\.", re.I)
_RE_SYSTEMD_STOPPED = re.compile(r"systemd\[1\]:\s*Stopped\s+(.+?)\.", re.I)
_RE_SYSTEMD_DEACTIVATED = re.compile(
    r"systemd\[1\]:\s*llm-router\.service:\s*Deactivated\s+successfully\.", re.I
)
_RE_SYSTEMD_CONSUMED = re.compile(
    r"systemd\[1\]:\s*llm-router\.service:\s*Consumed\s+(.+?)\s+CPU time,\s*(.+?)\s+memory peak",
    re.I,
)


@dataclass
class ServiceEvent:
    """Represents a systemd service lifecycle event."""

    event_type: str  # 'starting', 'started', 'stopping', 'stopped', 'deactivated'
    description: str
    resources: Dict[str, str] | None = None


class LogParser:
    def __init__(self) -> None:
        self._model: str | None = None
        self._model_path: str | None = None
        self._model_port: int | None = None
        self._tasks: List[Dict[str, Any]] = []
        self._checkpoints: List[Dict[str, Any]] = []
        self._service_events: List[ServiceEvent] = []
        # temporary holder for the most recent task (used by checkpoint detection)
        self._last_task: Dict[str, Any] | None = None

    # --------------------------------------------------------------------- #
    # Public API
    # --------------------------------------------------------------------- #

    def feed_line(self, line: str) -> None:
        """Consume one log line, updating internal state."""
        line = line.strip()
        if not line:
            return

        # Model info
        m = _RE_MODEL.search(line)
        if m:
            self._model = m.group(1)
            return
        m = _RE_MODEL_ARGS.search(line)
        if m:
            self._model_path = m.group(1)
            self._model_port = int(m.group(2))
            return

        # Task launch
        m = _RE_TASK.search(line)
        if m:
            task_id = int(m.group(1))
            task_name = m.group(2)
            task: Dict[str, Any] = {"id": task_id, "name": task_name, "details": {}}
            self._tasks.append(task)
            self._last_task = task
            return

        # n_past
        m = _RE_NPAST.search(line)
        if m:
            n = int(m.group(1))
            if self._last_task:
                self._last_task["details"]["n_past"] = n
            return

        # Checkpoint – attached to the most recent task
        m = _RE_CHECKPOINT.search(line)
        if m:
            idx = int(m.group(1))
            total = int(m.group(2))
            pos_min = int(m.group(3))
            pos_max = int(m.group(4))
            size = float(m.group(5))
            if self._last_task:
                self._last_task["details"]["checkpoint"] = {
                    "index": idx,
                    "total": total,
                    "pos_min": pos_min,
                    "pos_max": pos_max,
                    "size_mb": size,
                }
            self._checkpoints.append(
                {
                    "index": idx,
                    "total": total,
                    "pos_min": pos_min,
                    "pos_max": pos_max,
                    "size_mb": size,
                }
            )
            return

        # Eval timing – capture n_tokens and batch.n_tokens for the last task
        m = _RE_EVAL.search(line)
        if m:
            # groups: task_id, model_id, n_tokens, batch_n_tokens
            # we only need the n_tokens and batch_n_tokens for the latest task
            if self._last_task:
                self._last_task["details"]["eval"] = {
                    "n_tokens": int(m.group(3)),
                    "batch_n_tokens": int(m.group(4)),
                }
            return

        # Model args — already handled above
        # Model name — already handled above
        # Any other line we simply ignore for now

        # Systemd service lifecycle events
        m = _RE_SYSTEMD_STARTING.search(line)
        if m:
            self._service_events.append(
                ServiceEvent(event_type="starting", description=m.group(1))
            )
            return

        m = _RE_SYSTEMD_STARTED.search(line)
        if m:
            self._service_events.append(
                ServiceEvent(event_type="started", description=m.group(1))
            )
            return

        m = _RE_SYSTEMD_STOPPING.search(line)
        if m:
            self._service_events.append(
                ServiceEvent(event_type="stopping", description=m.group(1))
            )
            return

        m = _RE_SYSTEMD_DEACTIVATED.search(line)
        if m:
            self._service_events.append(
                ServiceEvent(
                    event_type="deactivated",
                    description="Service deactivated successfully",
                )
            )
            return

        m = _RE_SYSTEMD_STOPPED.search(line)
        if m:
            self._service_events.append(
                ServiceEvent(event_type="stopped", description=m.group(1))
            )
            return

        m = _RE_SYSTEMD_CONSUMED.search(line)
        if m:
            # Attach resource usage to the last stopped event
            cpu_time = m.group(1)
            memory = m.group(2)
            if self._service_events:
                last_event = self._service_events[-1]
                if last_event.resources is None:
                    last_event.resources = {}
                last_event.resources["cpu_time"] = cpu_time
                last_event.resources["memory_peak"] = memory
            return

    def state(self) -> Dict[str, Any]:
        """Return a snapshot of the parsed data."""
        return {
            "model": self._model,
            "model_path": self._model_path,
            "model_port": self._model_port,
            "tasks": [t.copy() for t in self._tasks],
            "checkpoints": list(self._checkpoints),
            "service_events": [
                {
                    "event_type": e.event_type,
                    "description": e.description,
                    "resources": e.resources,
                }
                for e in self._service_events
            ],
        }

    # --------------------------------------------------------------------- #
    # Convenience helpers (optional)
    # --------------------------------------------------------------------- #

    @staticmethod
    def parse_lines(lines: List[str]) -> Dict[str, Any]:
        """Parse a list of lines at once – thin wrapper around LogParser."""
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        return parser.state()


if __name__ == "__main__":
    # Simple demo – feed lines from stdin
    import sys

    parser = LogParser()
    for line in sys.stdin:
        parser.feed_line(line)
    print(parser.state())
