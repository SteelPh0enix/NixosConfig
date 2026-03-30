import sys
import unittest
from pathlib import Path

# Add the project root to sys.path before importing
sys.path.insert(0, str(Path(__file__).parent.parent))


class LogParserTests(unittest.TestCase):
    """Tests that verify the LogParser can capture model info, tasks and eval data."""

    def test_model_info(self) -> None:
        from log_parser import LogParser

        parser = LogParser()
        parser.feed_line("srv log_server_r: done request: GET / 192.168.0.150 200")
        parser.feed_line("srv          load_model: loading model 'my-model'")
        parser.feed_line(
            "srv          load: spawning server instance with name='my-model' on port 1234"
        )
        state = parser.state()
        self.assertEqual(state["model"], "my-model")
        self.assertEqual(state["model_path"], "my-model")
        self.assertEqual(state["model_port"], 1234)

    def test_task_parsing_with_details(self) -> None:
        from log_parser import LogParser

        # Synthetic log lines that follow the parser's expected format (simple space‑separated style).
        lines = [
            "srv slot launch_slot_: id 7 task my-task processing task, is_child = 0",
            "slot update_slots: id 7 task 0 n_past = 123",
            "slot update_slots: id 7 task 0 created context checkpoint 1 of 2 (pos_min = 4, pos_max = 5, n_tokens=***size = 20.3)",  # noqa: E501
            "slot print_timing: id 7 task 0 prompt eval time = 12.3ms n_tokens=20 batch.n_tokens=4567",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        self.assertEqual(len(state["tasks"]), 1)
        task = state["tasks"][0]
        self.assertEqual(task["id"], 7)
        self.assertEqual(task["name"], "my-task")
        details = task["details"]
        self.assertIn("n_past", details)
        self.assertEqual(details["n_past"], 123)
        self.assertIn("checkpoint", details)
        chk = details["checkpoint"]
        self.assertEqual(chk["index"], 1)
        self.assertEqual(chk["total"], 2)
        self.assertIn("size_mb", chk)
        self.assertAlmostEqual(chk["size_mb"], 20.3, places=1)
        self.assertIn("eval", details)
        eval_detail = details["eval"]
        self.assertEqual(eval_detail["n_tokens"], 20)
        self.assertEqual(eval_detail["batch_n_tokens"], 4567)

    def test_no_task_launch_when_none(self) -> None:
        from log_parser import LogParser

        lines = [
            "srv          load_model: loading model 'my-model'",
            "slot update_slots: id 1 task 0 n_past = 42",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()
        self.assertEqual(len(state["tasks"]), 0)

    def test_systemd_service_start_sequence(self) -> None:
        """Test detection of service startup sequence."""
        from log_parser import LogParser

        lines = [
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Starting LLM Router service - Multi-model llama-server...",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Started LLM Router service - Multi-model llama-server.",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        self.assertEqual(len(state["service_events"]), 2)
        self.assertEqual(state["service_events"][0]["event_type"], "starting")
        self.assertEqual(
            state["service_events"][0]["description"],
            "LLM Router service - Multi-model llama-server",
        )
        self.assertEqual(state["service_events"][1]["event_type"], "started")
        self.assertEqual(
            state["service_events"][1]["description"],
            "LLM Router service - Multi-model llama-server",
        )

    def test_systemd_service_stop_sequence(self) -> None:
        """Test detection of service stop sequence."""
        from log_parser import LogParser

        lines = [
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopping LLM Router service - Multi-model llama-server...",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: llm-router.service: Deactivated successfully.",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopped LLM Router service - Multi-model llama-server.",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        self.assertEqual(len(state["service_events"]), 3)
        self.assertEqual(state["service_events"][0]["event_type"], "stopping")
        self.assertEqual(state["service_events"][1]["event_type"], "deactivated")
        self.assertEqual(state["service_events"][2]["event_type"], "stopped")

    def test_systemd_resource_consumption(self) -> None:
        """Test detection of resource consumption stats."""
        from log_parser import LogParser

        lines = [
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopped LLM Router service - Multi-model llama-server.",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: llm-router.service: Consumed 7min 10.180s CPU time, 7.4G memory peak, 46.7M incoming IP traffic, 47M outgoing IP traffic.",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        # Resource consumption is attached to the last event
        self.assertEqual(len(state["service_events"]), 1)
        stopped_event = state["service_events"][0]
        self.assertEqual(stopped_event["event_type"], "stopped")
        self.assertEqual(stopped_event["resources"]["cpu_time"], "7min 10.180s")
        self.assertEqual(stopped_event["resources"]["memory_peak"], "7.4G")

    def test_systemd_full_restart_cycle(self) -> None:
        """Test a complete stop/start cycle with resource stats."""
        from log_parser import LogParser

        lines = [
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopping LLM Router service - Multi-model llama-server...",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: llm-router.service: Deactivated successfully.",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopped LLM Router service - Multi-model llama-server.",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: llm-router.service: Consumed 7min 10.180s CPU time, 7.4G memory peak, 46.7M incoming IP traffic, 47M outgoing IP traffic.",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Started LLM Router service - Multi-model llama-server.",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        # Resource consumption is attached to the last "stopped" event
        self.assertEqual(len(state["service_events"]), 4)
        self.assertEqual(state["service_events"][0]["event_type"], "stopping")
        self.assertEqual(state["service_events"][1]["event_type"], "deactivated")
        self.assertEqual(state["service_events"][2]["event_type"], "stopped")
        self.assertEqual(
            state["service_events"][2]["resources"]["cpu_time"], "7min 10.180s"
        )
        self.assertEqual(state["service_events"][2]["resources"]["memory_peak"], "7.4G")
        self.assertEqual(state["service_events"][3]["event_type"], "started")

    def test_systemd_with_tasks_killed(self) -> None:
        """Test tracking tasks that were active before service stop."""
        from log_parser import LogParser

        lines = [
            "srv slot launch_slot_: id 7 task my-task processing task, is_child = 0",
            "slot update_slots: id 7 task 0 n_past = 123",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: Stopping LLM Router service - Multi-model llama-server...",
            "mar 28 22:48:08 RX-78-FPC systemd[1]: llm-router.service: Deactivated successfully.",
        ]
        parser = LogParser()
        for line in lines:
            parser.feed_line(line)
        state = parser.state()

        # Should have 1 task and 2 service events
        self.assertEqual(len(state["tasks"]), 1)
        self.assertEqual(len(state["service_events"]), 2)
        self.assertEqual(state["tasks"][0]["id"], 7)
        self.assertEqual(state["tasks"][0]["name"], "my-task")
        self.assertEqual(state["service_events"][0]["event_type"], "stopping")
        self.assertEqual(state["service_events"][1]["event_type"], "deactivated")


if __name__ == "__main__":
    unittest.main()
