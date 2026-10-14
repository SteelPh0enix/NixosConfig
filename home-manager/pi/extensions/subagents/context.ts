// What every tool handler and the `/subagents` command need: the loaded config, the task registry and the lazily
// opened lease store. Built once in index.ts and handed to the per-tool modules, which keeps the shared mutable
// state out of each handler's signature.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { SubagentConfig } from "./config.ts";
import type { LeaseStore } from "./store.ts";
import type { TaskRegistry } from "./task-registry.ts";

export interface SubagentContext {
  pi: ExtensionAPI;
  configs: Map<string, SubagentConfig>;
  names: string[];
  groups: Map<string, number>;
  slots: Map<string, number>;
  registry: TaskRegistry;
  /** Opens the shared lease store on first use; an untracked subagent never calls it. */
  getStore: () => LeaseStore;
}
