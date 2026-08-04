#!/usr/bin/env python3
"""
Simple HTTP server with SSE endpoint for streaming journalctl logs.
Run as: python3 /etc/nixos/services/llm-logs-server/server.py [--service <unit>] [--port <port>]
Then visit: http://localhost:51581  (native) / http://localhost:51569 (ROCm)
"""

import os
import subprocess
import threading
import queue
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

# Get the directory where this script is located
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HTML_FILE = os.path.join(SCRIPT_DIR, "index.html")

LOG_QUEUE: queue.Queue[str] = queue.Queue()
SERVICE_NAME = "llm-router"
PORT = 51581


def stream_logs() -> None:
    """Continuously stream logs from journalctl via subprocess."""
    try:
        proc = subprocess.Popen(
            ["journalctl", "-fu", SERVICE_NAME, "--no-pager"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

        if proc.stdout is not None:
            for line in proc.stdout:
                LOG_QUEUE.put(line.rstrip())
    except Exception as e:
        LOG_QUEUE.put(f"[ERROR] {e}")


class LogHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: str) -> None:
        """Suppress default logging."""
        pass

    def do_GET(self) -> None:
        if self.path == "/":
            self.send_html()
        elif self.path == "/logs":
            self.send_sse()
        else:
            self.send_error(404)

    def send_html(self) -> None:
        """Serve the HTML interface from external file."""
        try:
            with open(HTML_FILE, "r", encoding="utf-8") as f:
                html = f.read()
        except FileNotFoundError:
            self.send_error(500, "HTML template not found")
            return

        # Substitute the service label into the shared template so the page
        # says which llama-server variant it's showing logs for.
        label = SERVICE_NAME.replace("-service", "").replace("_", " ").upper()
        html = html.replace("__SERVICE_LABEL__", label)

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode())

    def send_sse(self) -> None:
        """Serve SSE endpoint for streaming logs."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        # Send recent historical logs first
        try:
            proc = subprocess.Popen(
                [
                    "journalctl",
                    "-u",
                    SERVICE_NAME,
                    "--no-pager",
                    "-n",
                    "100",
                    "--since",
                    "1 hour ago",
                ],
                stdout=subprocess.PIPE,
                text=True,
            )
            if proc.stdout is not None:
                for line in proc.stdout:
                    self.wfile.write(f"event: log\ndata: {line.rstrip()}\n\n".encode())
                self.wfile.flush()
        except Exception as e:
            self.wfile.write(
                f"event: log\ndata: [ERROR fetching history: {e}]\n\n".encode()
            )
            self.wfile.flush()

        # Then stream new logs
        while True:
            try:
                line = LOG_QUEUE.get(timeout=1)
                self.wfile.write(f"event: log\ndata: {line}\n\n".encode())
                self.wfile.flush()
            except queue.Empty:
                # Send keepalive comment to prevent connection timeout
                try:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
                except BrokenPipeError:
                    break
            except (BrokenPipeError, ConnectionResetError):
                break


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in separate threads."""

    daemon_threads = True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stream systemd journal logs for an llm-router service over SSE."
    )
    parser.add_argument(
        "--service",
        default="llm-router",
        help="systemd unit name to follow (default: llm-router). For the ROCm "
        "variant pass 'llm-router-rocm'.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=51581,
        help="HTTP port to listen on (default: 51581).",
    )
    parser.add_argument(
        "--host",
        default="[IP_ADDRESS]",
        help="Bind address (default: [IP_ADDRESS], the LAN host interface).",
    )
    args = parser.parse_args()

    global SERVICE_NAME, PORT
    SERVICE_NAME = args.service
    PORT = args.port

    print(f"☤ {SERVICE_NAME} Log Server")
    print(f"  Starting journalctl stream for '{SERVICE_NAME}' service...")

    thread = threading.Thread(target=stream_logs, daemon=True)
    thread.start()

    server = ThreadingHTTPServer((args.host, PORT), LogHandler)
    print(f"  Web interface: http://localhost:{PORT}")
    print("  Press Ctrl+C to stop\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
