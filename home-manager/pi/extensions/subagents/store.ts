// Group concurrency accounting for the subagents extension.
//
// A subagent may belong to one or more "groups"; each group has a maximum
// number of subagents that may run at once, enforced across every pi instance
// (there can be several, e.g. multiple terminals) via a shared SQLite file.
//
// Enforcement is a lease, not a bare counter, so a crashed instance cannot
// deadlock a group: each lease expires after LEASE_TTL_MS with no heartbeat and
// is reaped by any instance. A heartbeat renews active leases so long tasks do
// not free their slot early.

import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { join } from "node:path";

/** A request to hold one slot in a group for a subagent. */
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
}

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
    this.db.exec("PRAGMA journal_mode=WAL");
    this.db.exec("PRAGMA busy_timeout=2000");
    this.db.exec(`CREATE TABLE IF NOT EXISTS leases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      grp TEXT NOT NULL,
      subagent TEXT NOT NULL,
      instance_id TEXT NOT NULL,
      pid INTEGER NOT NULL,
      acquired_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    )`);
    this.db.exec("CREATE INDEX IF NOT EXISTS idx_leases_grp_expires ON leases (grp, expires_at)");
  }

  /**
   * Hold a slot in each requested group for `subagent`, atomically.
   * Returns the created lease ids, or null if any group is full (nothing reserved).
   * Database problems throw, so a broken store is never mistaken for a full group.
   */
  acquire(subagent: string, requests: LeaseRequest[]): number[] | null {
    if (requests.length === 0) return [];
    this.assertOpen();
    const now = Date.now();
    const ids: number[] = [];
    const live = this.db.prepare("SELECT COUNT(*) AS c FROM leases WHERE grp = ? AND expires_at > ?");
    const ins = this.db.prepare(
      "INSERT INTO leases (grp, subagent, instance_id, pid, acquired_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
    );
    const reap = this.db.prepare("DELETE FROM leases WHERE grp = ? AND expires_at <= ?");
    this.db.exec("BEGIN IMMEDIATE");
    let committed = false;
    try {
      for (const { group, limit } of requests) {
        reap.run(group, now);
        if ((live.get(group, now) as { c: number })?.c >= limit) return null;
        const info = ins.run(group, subagent, this.instanceId, process.pid, now, now + LEASE_TTL_MS);
        ids.push(info.lastInsertRowid as number);
      }
      this.db.exec("COMMIT");
      committed = true;
      return ids;
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

  /** All active leases, for the `/subagents leases` command. */
  list(): Lease[] {
    if (this.closed) return [];
    return this.db
      .prepare(
        `SELECT id, grp, subagent, instance_id AS instanceId, pid,
                acquired_at AS acquiredAt, expires_at AS expiresAt
         FROM leases ORDER BY grp, subagent`,
      )
      .all() as unknown as Lease[];
  }

  /** Start the reap + heartbeat timers (idempotent). Call once per process. */
  start(): void {
    if (this.started || this.closed) return;
    this.started = true;
    this.reap();
    this.heartbeat();
    this.reapTimer = setInterval(() => this.reap(), REAP_INTERVAL_MS);
    this.heartbeatTimer = setInterval(() => this.heartbeat(), HEARTBEAT_INTERVAL_MS);
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
