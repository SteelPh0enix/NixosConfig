// The llama.cpp server behind pi's model: where it lives, whether it is one at all, and the two endpoints the
// footer reads. Nothing here knows about pi's request; `state.ts` decides what to do with what comes back.

import { debug } from "./debug.ts";

export type Slot = {
  id?: number;
  n_ctx?: number;
  is_processing?: boolean;
  n_prompt_tokens?: number;
  n_prompt_tokens_processed?: number;
  n_prompt_tokens_cache?: number;
  next_token?: { n_decoded?: number }[];
};

export type Timings = {
  cache_n?: number;
  prompt_n?: number;
  prompt_per_second?: number;
  predicted_n?: number;
  predicted_per_second?: number;
  draft_n?: number;
  draft_n_accepted?: number;
};

export type Metrics = {
  deferred?: number;
  processing?: number;
  busy?: number;
  accepted?: number;
  drafted?: number;
  nmax?: number;
};

const PROBE_TIMEOUT_MS = 1500;

/** `root|instance`, which is what both /metrics caches and the measured speeds are kept under. */
export const keyOf = (r: { root: string; instance: string }): string => `${r.root}|${r.instance}`;

export function serverRoot(m: { baseUrl?: string } | undefined): string | undefined {
  if (!m?.baseUrl) return undefined;
  try {
    const url = new URL(m.baseUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/v1$/, "");
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

/** Which machine this is, short enough for a detail cell: `pc:51536`, `local:33333`. */
export const shortHost = (root: string): string => {
  try {
    const url = new URL(root);
    const loopback = ["localhost", "127.0.0.1", "0.0.0.0", "::1"].includes(url.hostname);
    const name = loopback ? "local" : (url.hostname.split(".").at(-1) ?? url.hostname);
    return url.port ? `${name}:${url.port}` : name;
  } catch {
    return root;
  }
};

/** Settled "is this a llama.cpp server" answers; unknown roots are treated as one. */
const llamaRoots = new Map<string, boolean>();
const probing = new Set<string>();

/** One /props per server, off the request path: it decides polling, timings injection and whether to take the footer at all. */
export function probeRoot(root: string, onAnswer: (answer: boolean) => void): void {
  if (llamaRoots.has(root) || probing.has(root)) return;
  probing.add(root);
  fetch(`${root}/props`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
    .then(async (response) => {
      if (!response.ok) return false;
      const props = (await response.json()) as { role?: string; model_alias?: string; chat_template_caps?: unknown };
      return props.role === "router" || typeof props.model_alias === "string" || props.chat_template_caps !== undefined;
    })
    .catch(() => false)
    .then((answer) => {
      llamaRoots.set(root, answer);
      probing.delete(root);
      debug(`${root}: llama.cpp=${answer}`);
      onAnswer(answer);
    });
}

export const isLlama = (root: string | undefined): boolean => (root === undefined ? false : llamaRoots.get(root) ?? true);

export async function fetchSlots(root: string, instance: string): Promise<Slot[] | undefined> {
  try {
    const response = await fetch(`${root}/slots?${new URLSearchParams({ model: instance })}`, { signal: AbortSignal.timeout(1500) });
    if (!response.ok) return undefined;
    return (await response.json()) as Slot[];
  } catch (error) {
    debug(`/slots: ${error instanceof Error ? error.message : String(error)}`);
    return undefined;
  }
}

/** The slot carrying our request: a processing one, else the busiest. Exact only with --parallel 1. */
export function pickSlot(slots: Slot[]): Slot | undefined {
  if (slots.length === 0) return undefined;
  return slots.find((slot) => slot.is_processing) ?? slots.reduce((a, b) => ((b.n_prompt_tokens ?? 0) > (a.n_prompt_tokens ?? 0) ? b : a));
}

/** Optional per-instance metrics; `false` means this server has no /metrics endpoint at all. */
export const metricsSupport = new Map<string, boolean>();

function parseMetrics(text: string): Metrics {
  const value = (name: string): number | undefined => {
    const found = new RegExp(`^llamacpp:${name} (\\S+)$`, "m").exec(text);
    return found ? Number(found[1]) : undefined;
  };
  return {
    deferred: value("requests_deferred"),
    processing: value("requests_processing"),
    busy: value("n_busy_slots_per_decode"),
    accepted: value("spec_decode_num_accepted_tokens_total"),
    drafted: value("spec_decode_num_draft_tokens_total"),
    nmax: value("n_tokens_max"),
  };
}

/**
 * autoload=false is required: on a router /metrics is proxied per model and a plain read would load the
 * instance. The rate gauges are not read at all, since every scrape resets the buckets behind them.
 */
async function fetchMetrics(root: string, instance: string): Promise<Metrics | "off" | undefined> {
  try {
    const response = await fetch(`${root}/metrics?${new URLSearchParams({ model: instance, autoload: "false" })}`, { signal: AbortSignal.timeout(1500) });
    if (response.ok) return parseMetrics(await response.text());
    // 501 "Start it with --metrics" is the only answer that means there is no /metrics; anything else, including a
    // router refusing to speak for an instance that is not loaded, is worth asking about again.
    return response.status === 501 && /does not support metrics/i.test(await response.text()) ? "off" : undefined;
  } catch {
    return undefined;
  }
}

/** The last scrape per server+instance, so a request whose first scrape is late or lost does not show a row of dashes. */
export const metricsShown = new Map<string, Metrics>();

let scraping = false;

/** One scrape at a time; `undefined` means there is nothing new to show, `false` support means never again. */
export async function scrapeMetrics(root: string, instance: string): Promise<Metrics | undefined> {
  const key = keyOf({ root, instance });
  if (scraping || metricsSupport.get(key) === false) return undefined;
  scraping = true;
  try {
    const result = await fetchMetrics(root, instance);
    if (result === "off") {
      metricsSupport.set(key, false);
      debug(`${key}: no /metrics`);
      return undefined;
    }
    if (!result) return undefined; // cold instance or a hiccup: ask again next time
    metricsSupport.set(key, true);
    metricsShown.set(key, result);
    return result;
  } finally {
    scraping = false;
  }
}
