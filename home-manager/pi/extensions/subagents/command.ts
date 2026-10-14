// The `/subagents` command: task listing/detail/kill, and the lease management subcommands.

import type { ExtensionCommandContext, RegisteredCommand } from "@earendil-works/pi-coding-agent";
import type { SubagentContext } from "./context.ts";
import { formatDetail, formatStatusLine } from "./format.ts";
import { killTask } from "./kill.ts";
import { emitStatus } from "./ui.ts";

/** Minimal view of the command context the lease helpers need. */
type NotifyCtx = { ui: { notify: (message: string, type?: "info" | "warning" | "error") => void } };

/** True if a process with this pid currently exists (signal 0 probe). */
function isPidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    // ESRCH: no such process. Anything else (e.g. EPERM) means it is alive.
    return (err as NodeJS.ErrnoException).code === "ESRCH" ? false : true;
  }
}

/** `/subagents leases ...` — inspect and clean up group concurrency leases. */
async function handleLeases(deps: SubagentContext, args: string[], ctx: NotifyCtx): Promise<void> {
  const leaseStore = deps.getStore();
  const sub = args[0];

  if (!sub || sub === "list") {
    const leases = leaseStore.list();
    if (leases.length === 0) {
      ctx.ui.notify("subagents: no active leases");
      return;
    }
    const now = Date.now();
    const lines = leases.map((l) => {
      const when = new Date(l.expiresAt).toISOString();
      const secsLeft = Math.max(0, Math.round((l.expiresAt - now) / 1000));
      return `${l.grp} (${l.resKey}) · ${l.subagent} · pid ${l.pid} · expires ${when} (+${secsLeft}s)`;
    });
    ctx.ui.notify(`subagents: ${leases.length} active lease(s):\n${lines.join("\n")}`);
    return;
  }

  if (sub === "purge") {
    const expired = leaseStore.reap();
    const now = Date.now();
    let dead = 0;
    for (const l of leaseStore.list()) {
      if (l.expiresAt > now && !isPidAlive(l.pid)) {
        leaseStore.release(l.id);
        dead += 1;
      }
    }
    ctx.ui.notify(`subagents: purged ${expired} expired + ${dead} dead-instance lease(s)`);
    return;
  }

  if (sub === "drop-all") {
    const count = leaseStore.list().length;
    leaseStore.releaseAll();
    ctx.ui.notify(`subagents: dropped ${count} lease(s)`);
    return;
  }

  if (sub === "drop") {
    const group = args.slice(1).join(" ").trim();
    if (!group) {
      ctx.ui.notify("subagents: usage: /subagents leases drop <group>", "error");
      return;
    }
    const removed = leaseStore.dropGroup(group);
    ctx.ui.notify(`subagents: dropped ${removed} lease(s) for group "${group}"`);
    return;
  }

  ctx.ui.notify("subagents leases: list | purge | drop <group> | drop-all", "warning");
}

export function commandDefinition(deps: SubagentContext): Omit<RegisteredCommand, "name" | "sourceInfo"> {
  const { registry } = deps;
  return {
    description:
      "subagents: lists tasks; <id> shows one; kill <id> aborts one; leases lists/purges/drops group concurrency leases",
    getArgumentCompletions: (prefix) => {
      if (prefix.startsWith("kill ")) {
        const rest = prefix.slice("kill ".length);
        return registry
          .all()
          .filter((r) => r.state === "running" && r.id.startsWith(rest))
          .map((r) => ({ value: `kill ${r.id}`, label: `${r.id} (${r.name})` }));
      }
      return ["kill", "leases"]
        .filter((a) => a.startsWith(prefix))
        .map((value) => ({ value, label: value === "kill" ? "kill <id>" : value }));
    },
    handler: async (args: string, ctx: ExtensionCommandContext) => {
      const parts = args.trim().split(/\s+/).filter(Boolean);
      if (parts[0] === "leases") {
        await handleLeases(deps, parts.slice(1), ctx);
        return;
      }
      if (parts[0] === "kill") {
        const id = parts[1];
        if (!id) {
          ctx.ui.notify("subagents: usage: /subagents kill <id>", "error");
          return;
        }
        const record = registry.get(id);
        if (!record) {
          ctx.ui.notify(`subagents: no such task "${id}"`, "error");
          return;
        }
        const settled = await killTask(deps, record);
        ctx.ui.notify(
          `subagents: ${record.id} (${record.name}) → ${record.state}${settled ? "" : " (its cleanup is still winding down; the group slots were freed)"}`,
          record.state === "killed" ? "warning" : "info",
        );
      } else if (parts[0]) {
        const record = registry.get(parts[0]);
        if (!record) {
          ctx.ui.notify(`subagents: no such task "${parts[0]}"`, "error");
          return;
        }
        ctx.ui.notify(formatDetail(record));
      } else {
        const lines = registry.all().map(formatStatusLine);
        ctx.ui.notify(lines.length === 0 ? "subagents: no tasks" : lines.join("\n"));
      }
      emitStatus(deps.pi, registry);
    },
  };
}
