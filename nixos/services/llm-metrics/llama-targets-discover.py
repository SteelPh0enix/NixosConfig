#!/usr/bin/env python3
"""Discover loaded llama.cpp router models and emit a Prometheus file_sd file.

The llama-server instances in this setup run in multi-model "router" mode
(--models-max / --models-preset). In that mode the router's own /metrics
endpoint is a proxy that requires a ?model= parameter, so it cannot be
scraped directly. Instead, the router spawns a child llama-server per
loaded model (on a random port, --port 0) and the children serve plain
/metrics.

This script queries each router's /models endpoint, finds models whose
status is "loaded", reads the child's port from the recorded spawn args,
and writes a Prometheus file_sd JSON file with one target group per
(router, model) pair. Labels: server=<router label>, model=<model name>.

On a per-router query failure the previous targets for that router are
kept, so transient API hiccups do not flap scrape targets.

Usage: llama-targets-discover.py OUTPUT_FILE
"""

import json
import os
import sys
import tempfile
import urllib.error
import urllib.request

# router port -> "server" label (keep in sync with the scrape configs in
# llm-metrics.nix and the router services' --port flags)
ROUTERS = {
    "51580": "llm-router",
    "51536": "llm-router-rocm",
}

TIMEOUT = 5  # seconds, per router request


def log(msg):
    print(f"llama-targets-discover: {msg}", flush=True)


def fetch_loaded_models(router_port):
    """Return {model_name: child_port} for one router, or None on error."""
    url = f"http://127.0.0.1:{router_port}/models"
    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "llama-targets-discover/1.0"}
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError) as e:
        log(f"router {router_port}: failed to query /models: {e}")
        return None

    loaded = {}
    for model in data.get("data", []):
        status = model.get("status", {})
        if status.get("value") != "loaded":
            continue
        # the child's real port is recorded in the spawn args (--port N)
        args = status.get("args", [])
        child_port = None
        for i, arg in enumerate(args):
            if arg == "--port" and i + 1 < len(args):
                try:
                    child_port = int(args[i + 1])
                except ValueError:
                    child_port = None
                break
        if child_port is None or not 0 < child_port < 65536:
            log(
                f"router {router_port}: model {model.get('id')!r} is loaded "
                "but has no valid child port; skipping"
            )
            continue
        loaded[model["id"]] = child_port
    return loaded


def read_previous(path):
    """Return the previous file's target groups, or [] if absent/invalid."""
    try:
        with open(path) as f:
            groups = json.load(f)
        if isinstance(groups, list):
            return groups
    except (OSError, json.JSONDecodeError):
        pass
    return []


def previous_groups_for(groups, server):
    return [
        g
        for g in groups
        if isinstance(g, dict) and g.get("labels", {}).get("server") == server
    ]


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} OUTPUT_FILE", file=sys.stderr)
        return 2
    path = sys.argv[1]

    previous = read_previous(path)
    groups = []
    for router_port, server in ROUTERS.items():
        loaded = fetch_loaded_models(router_port)
        if loaded is None:
            kept = previous_groups_for(previous, server)
            log(f"router {router_port} ({server}): keeping {len(kept)} previous target(s)")
            groups.extend(kept)
            continue
        for model, child_port in sorted(loaded.items()):
            groups.append(
                {
                    "targets": [f"127.0.0.1:{child_port}"],
                    "labels": {"server": server, "model": model},
                }
            )
        log(f"router {router_port} ({server}): {len(loaded)} loaded model(s)")

    # atomic write so prometheus never sees a partially written file
    directory = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(prefix=".llama-targets.", dir=directory)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(groups, f, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

    log(f"wrote {len(groups)} target group(s) to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
