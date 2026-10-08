// Group concurrency accounting for the subagents extension.
//
// A subagent may belong to one or more "groups"; a group's limit is how many *distinct models* may hold it at
// once (mirrors the router's `--models-max 1`), and within one model the capacity is that model's own slot count
// (its `--parallel`). So the same limit now reads two dimensions: which model, and how many of it.
//
// Enforcement is a lease, not a bare counter, so a crashed instance cannot deadlock a group: each lease expires
// after LEASE_TTL_MS with no heartbeat and is reaped by any instance. A heartbeat renews active leases so long
// tasks do not free their slot early.

import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

/**
 * One spawn's claim on the model it runs, shared by every group it asks for: `key` is "provider/model", so two
 * models never share a lease; `capacity` is that model's slot count; `claim` is one id for the whole spawn, so a
 * spawn holding two groups counts once toward capacity.
 */
export interface SpawnClaim {
  key: string;
  capacity: number;
  claim: string;
}

/** A request to hold one slot in one group, whose limit counts distinct models. */
export interface LeaseRequest {
  group: string;
  limit: number;
}

/** A row in the lease table: one held slot. */
export interface Lease {
  id: number;
  grp: string;
  subagent: string;
  instanceId: string;
  pid: number;
  acquiredAt: number;
  expiresAt: number;
  /** The model this slot is on ("provider/model"); different models never share a res_key. */
  resKey: string;
  /** One id per spawn, shared by every group a single spawn takes, so capacity counts the spawn once. */
  claim: string;
}

/**
 * The outcome of a claim. `ok` is a spawn that took its slot(s), with the `slot` label it was handed (which of this
 * model's live slots it is, out of its slot count). `resident` means the group is already holding its limit of other
 * models, and says which; `full` means this model's own slots are gone. `at` names the model in the way, so the
 * caller can say exactly why a spawn was refused.
 */
export type AcquireResult =
  | { ok: true; ids: number[]; slot: { index: number; total: number } }
  | { ok: false; reason: "resident"; group: string; at: string; limit: number }
  | { ok: false; reason: "full"; at: string; capacity: number };

/** Keep a lease alive this long without a heartbeat before it counts as dead. */
const LEASE_TTL_MS = 90_000;
/** Renew a lease once it falls within this window of expiring. */
const HEARTBEAT_MARGIN_MS = 15_000;
const HEARTBEAT_INTERVAL_MS = 20_000;
const REAP_INTERVAL_MS = 30_000;

export class LeaseStore {
  private readonly db: DatabaseSync;
  private readonly instanceId: string;
  private started = false;
  private closed = false;
  private reapTimer?: ReturnType<typeof setInterval>;
  private heartbeatTimer?: ReturnType<typeof setInterval>;

  constructor(dbPath: string, instanceId: string) {
    this.instanceId = instanceId;
    mkdirSync(join(dbPath, ".."), { recursive: true });
    this.db = new DatabaseSync(dbPath);
    // busy_timeout first: converting a fresh database to WAL wants an exclusive lock, and two pi instances opening
    // the shared store in the same moment can lose it ("database is locked") with nothing to wait on.
    this.db.exec("PRAGMA busy_timeout=2000");
    this.db.exec("PRAGMA journal_mode=WAL");
    this.db.exec(`CREATE TABLE IF NOT EXISTS leases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      grp TEXT NOT NULL,
      subagent TEXT NOT NULL,
      instance_id TEXT NOT NULL,
      pid INTEGER NOT NULL,
      acquired_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      res_key TEXT NOT NULL DEFAULT '',
      claim TEXT NOT NULL DEFAULT ''
    )`);
    this.db.exec("CREATE INDEX IF NOT EXISTS idx_leases_grp_expires ON leases (grp, expires_at)");
    this.db.exec("CREATE INDEX IF NOT EXISTS idx_leases_res_key ON leases (res_key)");
  }

  /**
   * Hold a slot in each requested group for one spawn, atomically. A group's limit counts *distinct models*, and
   * the model's own capacity counts *distinct spawns* across every group — so a multi-group spawn takes its slots
   * once, and one model reached through two groups cannot run more than its slot count. The verdict says which
   * model stood in the way; nothing is written on a refusal (the transaction rolls back whole).
   * Database problems throw, so a broken store is never mistaken for a full group.
   */
  acquire(subagent: string, spawn: SpawnClaim, requests: LeaseRequest[]): AcquireResult {
    this.assertOpen();
    const now = Date.now();
    const ids: number[] = [];
    const ins = this.db.prepare(
      "INSERT INTO leases (grp, subagent, instance_id, pid, acquired_at, expires_at, res_key, claim) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    );
    const reap = this.db.prepare("DELETE FROM leases WHERE grp = ? AND expires_at <= ?");
    const others = this.db.prepare(
      "SELECT DISTINCT res_key FROM leases WHERE grp = ? AND res_key <> ? AND expires_at > ?",
    );
    const countThis = this.db.prepare(
      "SELECT COUNT(DISTINCT claim) AS c FROM leases WHERE res_key = ? AND expires_at > ?",
    );
    const { key, capacity, claim } = spawn;
    this.db.exec("BEGIN IMMEDIATE");
    let committed = false;
    try {
      // Residency, per group: reject if the group already holds `limit` distinct models other than this one.
      for (const { group, limit } of requests) {
        reap.run(group, now);
        const holding = (others.all(group, key, now) as Array<{ res_key: string }>).map((r) => r.res_key);
        if (holding.length >= limit) {
          this.db.exec("ROLLBACK");
          return { ok: false, reason: "resident", group, at: holding.join(", "), limit };
        }
      }
      // Capacity, per model across all groups, counted as distinct spawns (not rows) plus the one about to be taken.
      const held = (countThis.get(key, now) as { c: number }).c;
      if (held + 1 > capacity) {
        this.db.exec("ROLLBACK");
        return { ok: false, reason: "full", at: key, capacity };
      }
      // Everything admitted: write one row per group, all carrying this spawn's claim. The slot label counts other
      // spawns, not rows — a label, not a reservation, so it shifts as others finish.
      for (const { group } of requests) {
        const info = ins.run(group, subagent, this.instanceId, process.pid, now, now + LEASE_TTL_MS, key, claim);
        ids.push(info.lastInsertRowid as number);
      }
      this.db.exec("COMMIT");
      committed = true;
      return { ok: true, ids, slot: { index: held + 1, total: capacity } };
    } finally {
      if (!committed) {
        try {
          this.db.exec("ROLLBACK");
        } catch {
          // The transaction was already gone; the original error stands.
        }
      }
    }
  }

  /** Renew this instance's leases that are about to expire. */
  heartbeat(): void {
    if (this.closed) return;
    const now = Date.now();
    this.db
      .prepare("UPDATE leases SET expires_at = ? WHERE instance_id = ? AND expires_at <= ?")
      .run(now + LEASE_TTL_MS, this.instanceId, now + HEARTBEAT_MARGIN_MS);
  }

  /** Remove expired leases; returns how many were removed. */
  reap(): number {
    if (this.closed) return 0;
    return Number(this.db.prepare("DELETE FROM leases WHERE expires_at <= ?").run(Date.now()).changes);
  }

  /** Remove all of this instance's leases (on clean shutdown). */
  releaseAll(): void {
    if (this.closed) return;
    this.db.prepare("DELETE FROM leases WHERE instance_id = ?").run(this.instanceId);
  }

  /** Remove one lease by id (on task completion). */
  release(id: number): void {
    if (this.closed) return;
    this.db.prepare("DELETE FROM leases WHERE id = ?").run(id);
  }

  /** Remove all leases for a group; returns the count removed. */
  dropGroup(group: string): number {
    if (this.closed) return 0;
    return Number(this.db.prepare("DELETE FROM leases WHERE grp = ?").run(group).changes);
  }

  /** The leases that still count. An expired one is a slot somebody may already be taking, so it is not listed. */
  list(): Lease[] {
    if (this.closed) return [];
    return this.db
      .prepare(
        `SELECT id, grp, subagent, instance_id AS instanceId, pid,
                acquired_at AS acquiredAt, expires_at AS expiresAt, res_key AS resKey, claim
         FROM leases WHERE expires_at > ? ORDER BY grp, subagent`,
      )
      .all(Date.now()) as unknown as Lease[];
  }

  /** Start the reap + heartbeat timers (idempotent). Call once per process. */
  start(): void {
    if (this.started || this.closed) return;
    this.started = true;
    this.reap();
    this.heartbeat();
    // A locked database in a timer would take pi down with it; the next tick tries again, and acquire() reaps anyway.
    this.reapTimer = setInterval(() => {
      try {
        this.reap();
      } catch {
        // busy or closed
      }
    }, REAP_INTERVAL_MS);
    this.heartbeatTimer = setInterval(() => {
      try {
        this.heartbeat();
      } catch {
        // busy or closed
      }
    }, HEARTBEAT_INTERVAL_MS);
    this.reapTimer.unref?.();
    this.heartbeatTimer.unref?.();
  }

  /** Stop the timers, free this instance's slots, and close the database. */
  close(): void {
    if (this.closed) return;
    clearInterval(this.reapTimer);
    clearInterval(this.heartbeatTimer);
    this.releaseAll();
    this.closed = true;
    this.db.close();
  }

  private assertOpen(): void {
    if (this.closed) throw new Error("subagent lease store is closed");
  }
}
