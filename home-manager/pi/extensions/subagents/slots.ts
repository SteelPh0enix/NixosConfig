// Model slot discovery for the subagents extension.
//
// The router on this box runs one preset at a time (`--models-max 1`), so a group's limit means
// "how many distinct models may hold it at once" and, within one model, the capacity is that model's
// slot count (llama.cpp's `--parallel`). This module resolves that slot count, in order:
//
//   1. an explicit override in subagents.json — `"slots": { "provider/model": 4 }`,
//   2. then the server's own `/v1/models`, where each preset's `status.args` names its `--parallel`,
//   3. then `1` (today's behaviour).
//
// Discovery reads only `/v1/models`, never anything that could load or swap a model, and a server that does not
// answer simply means one slot — it is never fatal, so a quiet router never blocks a spawn on its own.

/** Cache a discovered slot count this long before asking the server again. */
const DISCOVERY_TTL_MS = 30_000;
const PROBE_TIMEOUT_MS = 2000;

type RouterModel = {
  id: string;
  status?: { value?: string; failed?: boolean; args?: string[] };
};

/**
 * Turn an inference baseUrl (ends with `/v1`) into the server root that answers `/props` and `/v1/models`.
 * A baseUrl without `/v1` is left as-is; anything unparseable is not a router we can ask.
 */
function serverRoot(baseUrl: string): string | undefined {
  try {
    const url = new URL(baseUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

/** Fetch a URL that answers quickly and never loads a model; never throws, always JSON or `undefined`. */
async function getJson<T>(url: string, signal?: AbortSignal): Promise<T | undefined> {
  const timeout = AbortSignal.timeout(PROBE_TIMEOUT_MS);
  const linked = signal ? AbortSignal.any([signal, timeout]) : timeout;
  try {
    const response = await fetch(url, { signal: linked });
    if (!response.ok) return undefined;
    return JSON.parse(await response.text()) as T;
  } catch {
    return undefined;
  }
}

/** Read `--parallel N` out of a preset's launch args; an absent or invalid flag means one request at a time. */
export function parallelFromArgs(args: string[] | undefined): number {
  const list = args ?? [];
  for (let i = 0; i < list.length - 1; i++) {
    if (list[i] !== "--parallel") continue;
    const n = Number(list[i + 1]);
    if (Number.isSafeInteger(n) && n >= 1) return n;
  }
  return 1;
}

/** An override beats the server, which beats 1; anything below 1 or non-integer falls through to the server. */
function pickSlot(discovered: number, override?: number): number {
  if (override !== undefined && Number.isInteger(override) && override >= 1) return override;
  return discovered >= 1 ? discovered : 1;
}

/**
 * Resolves one model's slot count from its provider. Discovery is cached per provider for ~30 s and refreshed
 * lazily on first use, so the spawn handler asks the server at most once per 30 s per provider and never on the
 * request path more than that.
 */
export class SlotResolver {
  private readonly root?: string;
  private readonly provider: string;
  /** provider/model -> discovered --parallel, and when it was read (to honour the TTL). */
  private readonly discovered = new Map<string, { slots: number; at: number }>();
  private refreshing?: Promise<void>;

  constructor(baseUrl: string, provider = "") {
    this.root = serverRoot(baseUrl);
    this.provider = provider;
  }

  /** Slots for one model — override, then `--parallel`, then 1 — cached per provider for ~30 s. */
  async slotsFor(providerModel: string, override?: number): Promise<number> {
    const cached = this.discovered.get(providerModel);
    if (!cached || Date.now() - cached.at >= DISCOVERY_TTL_MS) {
      await this.refresh();
    }
    const found = this.discovered.get(providerModel);
    return pickSlot(found?.slots ?? 1, override);
  }

  /** Read each preset's `--parallel` from `/v1/models` once and cache it; never loads or swaps a model. */
  async refresh(): Promise<void> {
    if (!this.root) return;
    if (this.refreshing) return this.refreshing;
    this.refreshing = (async () => {
      const models = (await getJson<{ data?: RouterModel[] }>(`${this.root}/v1/models`))?.data ?? [];
      const now = Date.now();
      // Key each preset by provider/model so a later slotsFor(provider/model) finds it; the model name is the preset
      // id pi resolved, so this matches the key a spawn builds for that same model.
      for (const model of models) {
        this.discovered.set(`${this.provider}/${model.id}`, { slots: parallelFromArgs(model.status?.args), at: now });
      }
    })().catch(() => {
      // A discovery failure leaves the cache as it was (empty on the first try, so the next read means 1 slot).
    });
    try {
      await this.refreshing;
    } finally {
      this.refreshing = undefined;
    }
  }
}
