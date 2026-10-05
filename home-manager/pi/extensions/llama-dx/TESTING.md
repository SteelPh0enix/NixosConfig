# Testing llama-dx

Three scripts in `test-utils/`, all plain node (they import the `.ts` files directly, node strips the types) and
none of them needs pi running:

| script | needs | use it for |
|---|---|---|
| `preview.mjs` | nothing | what the two lines look like at a given width |
| `check.mjs` | nothing (fakes llama.cpp) | polling, the moving bands of a request, the `/metrics` cells, taking pi's footer back |
| `harness.mjs` | a real llama.cpp instance | one real request end to end |

After a change: `preview.mjs --check` for the layout, `check.mjs` for anything else, then one `harness.mjs` run and
a real pi session before rebuilding the system.

**No live test may run on pi's default model.** The default model is the instance the testing agent itself is being
served by, so a request made through it is taken out of that agent's own KV cache — the session doing the testing
loses its context. Anything that reaches a server names the testing instance explicitly: `harness.mjs` pins
`--root http://steelph0enix.pc:51536` with `--model qwen-27B`, a pi run pins
`--provider llama-pc --model qwen-27B`. A live command carrying neither is a bug. `preview.mjs` and `check.mjs`
touch no server and no pi, so they are always safe.

## the layout: `node test-utils/preview.mjs`

```
node test-utils/preview.mjs [--width 80,120,160] [--only idle,prefilling] [--plain] [--check] [--legend] [--demo] [--cells 48]
```

Renders the real `metricGroups`/`metricsLine`/`baseLine` at chosen widths and phases (idle, prefilling, decoding,
near full, just compacted, no `--metrics`), so the look can be judged without starting pi. `--plain` prints without
colours, `--only` picks scenarios, `--legend` prints the `/llama-dx info` list instead of the footer.

`--demo` is the one to run after anything touches the bar: every combination of the bands (empty, one token held,
held, the whole incoming prompt before evaluation starts, mid-prefill, the three frontiers, all the real bands in
one cell, the forecast reaching past 90%, over capacity, unknown used, one generated token, past 70%, past 90%),
then one whole request through the bar and finishing, then the two lines at widths where identity has to give way.
`--cells 60` judges it at a real granularity. Its colours are the noctalia palette resolved by hand, so they match
the theme in use rather than the tokens; under `--plain` the pending track looks exactly like the free one, since
only their colours differ.

`--check` asserts the layout invariants at every width from 40 to 280 and exits non-zero: the base line is exactly
the terminal width, the metrics line never exceeds it (groups drop from the right instead), the bar keeps at least
ten cells, the number of filled cells is exactly the number of cells the real bands reach
(`ceil((used + evaluating + generating) / total * cells)`, no tolerance, since a band claims every cell it touches),
the cells reached once the forecast counts too match the same figure with `pending` added, the bands appear in
order, and every band's total coverage equals its share of the bar to the last decimal. The last three come from
`barCells()`, the coverage of the bar without glyphs or colours.

## the whole extension: `node test-utils/check.mjs`

```
node test-utils/check.mjs [--port 39451] [--dump]
```

Imports `../index.ts` — the extension as pi loads it — and drives it through `session_start`,
`before_provider_request`, `provider_stream_event`, `agent_end`, `/llama-dx reset` and `model_select` against a
fake llama.cpp on `127.0.0.1:<port>`, then renders the footer after every poll. Every assertion is printed and the
exit status is non-zero if any of them failed.

The fake follows a `step` counter **that the check itself advances**, so a run always takes the same steps and the
timers of the machine under test cannot change the outcome: a 10000-token prompt of which 4000 are cached, so 6000
have to be evaluated over eight steps of prefill (800 tokens each), generation starts at step twelve, and the slot
goes idle after step sixteen, which is what the idle detection needs to end the request. `/slots` answers the way
llama.cpp does: `n_prompt_tokens` is the slot's whole KV (`cache + processed + decoded`), never the size of this
prompt, and the first answer of a request still carries the task before it — different counters, a slot that is not
processing. What the check feeds `provider_stream_event` mirrors the same `step`: `prompt_progress` with
`total = 10000, cache = 4000, processed = 4000 + evaluated`, so the two sources always describe the same moment.
`/props` answers like a router everywhere except under `/nope`, where it answers like something that is not
llama.cpp. `/metrics` returns a fixed scrape (deferred, processing, `n_busy_slots_per_decode`, the
speculative-decode counters, `n_tokens_max`). At step thirteen one chunk carries `timings` with enough measured
tokens for llama.cpp's own speeds to be trusted, plus the exact `usage.prompt_tokens`.

A run takes about four seconds, since the extension is polled on its own timer and the check only reads the footer
in between.

What it asserts, in order:

- the footer is taken on a llama.cpp model, and stays taken while the request runs
- the live `pp` rate from `/slots` carries the `~`, and the server's own `pp`/`tg` (713 and 58 here) replace it once
  `timings` arrive
- the `q`/`fl`/`bd` cells appear once `/metrics` has answered
- prefill shows up in the evaluating band, generation in the generating one, and the two are separate; while the
  request runs the moving band lands on the held one in a shared cell (read from `barCells()`, not from the glyphs)
- the prompt still to evaluate is on the bar before it is evaluated and, from the first progress chunk on, only
  shrinks — to nothing; `pf` reads 100% exactly when the tokens have run out, never earlier, and never falls back
  while the request runs; those two are the shape of the bug this footer had, where `pf` leapt to 100% mid-prefill
- a `timings` chunk of a *running* request counts only what llama.cpp has evaluated so far, so it must not be taken
  for the whole prompt: a second request is fed one and must still show `fp 10k` and `pf 26.7%`
- a slot that has never been seen busy — a queue, a loading model, the previous task's counters still in `/slots` —
  ends nothing and lends nothing
- once the request ends, what it evaluated and produced joins the held band, so the bar keeps the committed tokens
- the prompt size is `~`-estimated first and becomes llama.cpp's exact 10k
- `tt` gets a value
- every indicator the metrics line can hold is explained by `/llama-dx info`, and so are the `~`, `—` and bright
  markers; the cells come from `metricGroups(view().facts)`, so a cell the legend does not know turns this red
- the request is counted, `/llama-dx reset` reports clearing, and a model whose server is not llama.cpp hands the
  footer back

`--dump` prints the footer as plain text at every poll after the results, which is how you tell whether the bar is
really moving rather than merely non-empty.

The assertions are worth something only if they fail when the thing they check is missing, so when adding one: cut
the fake short of what it needs (never deliver the `timings`, answer `/props` with `{}`) in a copy under `/tmp` and
watch that one assertion go red while the others stay green.

## a real instance: `node test-utils/harness.mjs`

```
node test-utils/harness.mjs [--root http://steelph0enix.pc:51536] [--model qwen-27B] [--ctx 32768] \
                            [--seconds 75] [--prompt <text>] [--repeat N] [--max-tokens 200]
```

The testing instance is the router on `steelph0enix.pc:51536`, which serves `qwen-27B` (`--props`, `--slots` and
`--metrics` all on). The stubbed pi hands the harness nothing, so the harness is the transport itself: it sends the
payload that `before_provider_request` returned to `POST /v1/chat/completions` with `stream: true`
and `stream_options.include_usage`, feeds every chunk into `provider_stream_event`, and prints the footer every
0.7s. `--seconds` covers a cold instance: the first lines show the model loading and the queue, then prefill, then
generation. `--repeat N` appends N copies of the prompt so prefill lasts long enough to watch and to measure — with
the default prompt (65 tokens out of the chat template) there is nothing for `pp` to measure and it stays `—`,
which is correct rather than broken.

A warm `qwen-27B`, four polls of one request, the middle of the bar elided so the lines fit here. `fp 2.2k` is
exact from the first render, because `prompt_progress` arrives before prefill has evaluated anything; `re 42` is the
cached prefix, so `pf` divides by 2183 and not by 2225. `pp` stays `—` until the window over `/slots` is long enough
to be a rate rather than one batch step, then takes llama.cpp's own from the chunks; the green `█` is the evaluating
band growing, the `▒` at its left edge is where it lands on the held band, the faint green in front of it is what is
left of the prompt to come, and the second `▒` from 4.2 is the first generated tokens landing on the evaluating band;
`tt` appears with the first content token:

```
  0.7 │ pp — tg — t/s │ fp  2.2k  ev     0  pf  0.00%  re    42  out    0 │ … │ q 0  fl  1/1  bd 1.00 │ tt —
      │ /home/dev/src/steel-pi (master)  9,200 6.38%  ██████▒░░░…░░░  144,128  qwen-27B • high
  2.8 │ pp  779 tg — t/s │ fp  2.2k  ev  1.7k  pf  76.4%  re    42  out    0 │ … │ tt —
      │ /home/dev/src/steel-pi (master)  9,200 6.38%  ██████▒██░░░…░░░  144,128  qwen-27B • high
  3.5 │ pp  836 tg — t/s │ fp  2.2k  ev  2.2k  pf  99.8%  re    42  out    0 │ … │ tt —
      │ /home/dev/src/steel-pi (master)  9,200 6.38%  ██████▒██░░░…░░░  144,128  qwen-27B • high
  4.2 │ pp  639 tg  44 t/s │ fp  2.2k  ev  2.2k  pf   100%  re    42  out   29 │ … │ tt   3.5s
      │ /home/dev/src/steel-pi (master)  9,200 6.38%  ██████▒█▒░░░…░░░  144,128  qwen-27B • high
```

`--prompt` with fresh text, not `--repeat`: a repeated prompt of the run before sits in the KV entirely, and then
`re` swallows it, `ev` is a handful of tokens and `pf` legitimately reads 100% at once.

The last lines carry the stream's own `usage` and `timings`, so the numbers in the cells can be checked against what
llama.cpp actually reported.

## types

`tsc` from nixpkgs, against pi's own `.d.ts` files: pi's runtime tree ships no dev dependencies, so there is no
`typescript` inside the install. The repo has no `node_modules`, and `tsc` finds them by walking up from the file it
is given, so the check runs on a copy with a symlink next to it; it follows imports, so naming only `index.ts` covers
all seven files.

```sh
TSC="$(nix build --no-link --print-out-paths nixpkgs#typescript)/bin/tsc"
pi_root=$(dirname "$(dirname "$(readlink -f "$(command -v pi)")")")   # /nix/store/…-pi-<version>
NM="$pi_root/lib/pi/node_modules"   # @types/node and pi's own types
rm -rf /tmp/dx-typecheck && mkdir -p /tmp/dx-typecheck && ln -s "$NM" /tmp/dx-typecheck/node_modules
cp ./*.ts /tmp/dx-typecheck/
cd /tmp/dx-typecheck && "$TSC" --noEmit --strict --noUnusedLocals --noImplicitOverride \
  --skipLibCheck --target es2023 --module esnext --moduleResolution bundler \
  --allowImportingTsExtensions --types node index.ts
```

## in pi itself

jiti, not node, loads the extension in pi, and it is handed the **directory** rather than `index.ts` because the
files import each other. home-manager links this directory to `~/.pi/agent/extensions/llama-dx`, so a plain `pi`
already loads it; `-e` adds a second copy and only makes sense for an unlinked checkout:

```sh
# the model is named, never left to the default: see the rule at the top
LLAMA_DX_DEBUG=1 pi --extension "$PWD" --provider llama-pc --model qwen-27B -p "reply with exactly: ok"
```

stderr then shows the verdict of the `/props` probe (`llama-dx: http://…: llama.cpp=true`) and the finished request
(`llama-dx: #1 prompt=… eval=… reuse=… out=… pp=… tg=…`). To confirm the Nix side copies the whole tree rather than
one file, build a throwaway derivation around `${./extensions/llama-dx}` and list its output; `home.file` links that
same store path into `~/.pi/agent/extensions`.

## what these do not cover

the colours as the terminal shows them (`preview.mjs --demo` paints the noctalia palette by hand; the assertions
only map theme tokens, never compare them against a theme file), the used zone under compaction or
branching in a real session, `--parallel > 1` (the fake answers with one slot, and the real instance is usually
idle at 1/1), and the fitted `pp` estimate, which only replaces the plain mean once a server has five measured
requests to fit against.
