{ lib, ... }:
{
  # ---- nvim-lint (external linters) ----
  # Fills the gaps LSP leaves open here: `fish -n` for fish (no fish server enabled),
  # statix + deadnix for Nix (nixd only reports parse/semantic errors), ruff for Python
  # (basedpyright is a type checker). Shell scripts are deliberately *not* here - see the
  # bashls note inside `lintersByFt` below.
  #
  # `autoInstall` resolves each name in `lintersByFt` to a nix package
  # (nvim-lint/packages.nix, else `pkgs.<name>`) and puts it in the nvim wrapper's PATH.
  plugins.lint = {
    enable = true;
    autoInstall.enable = true;

    # `lintersByFt` is a plain `attrsOf (listOf str)` *with defaults* (nixvim ships
    # text/markdown/rst -> vale, json -> jsonlint, ruby, janet, inko, clojure,
    # dockerfile -> hadolint, terraform -> tflint). Adding keys MERGES with those, and
    # autoInstall would then drag vale/jsonlint/hadolint/tflint into the wrapper -
    # `mkForce` replaces the whole attrset instead.
    # (Per-key `null` is not an option: the element type is `listOf str`, and
    #  `autoInstall.overrides.<name> = null` only skips the *package*, not the linter.)
    lintersByFt = lib.mkForce {
      fish = [ "fish" ]; # `fish -n` syntax check - no fish LSP enabled, so nothing overlaps
      nix = [
        "statix"
        "deadnix"
      ]; # nixd reports parse/semantic errors only, never these
      python = [ "ruff" ]; # basedpyright is a type checker; ruff adds the lint rules

      # NOT sh/bash -> shellcheck, even though it is the obvious entry:
      # adding shellcheck to the wrapper (lsp.nix, §1.1) means bash-language-server
      # lints with it out of the box - `shellcheckPath` defaults to `'shellcheck'`
      # ("an empty string will disable linting", server/out/config.js) - so nvim-lint
      # would publish the identical set a second time.
      # Measured on the built nvim, `:edit` of a script with one unquoted expansion:
      #   NAMESPACE shellcheck            count=2   (nvim-lint,  code = 2086)
      #   NAMESPACE nvim.lsp.bashls.1     count=2   (bashls,     code = SC2086)
      # The LSP side wins: it re-lints on change instead of only on `:w`, passes
      # `--shell`/`--external-sources` itself, and its results carry quickfix code actions.
      # If you ever want nvim-lint to own it instead, disable the server side with
      # `plugins.lsp.servers.bashls.settings.shellcheckPath = "";` and re-add it above.
      #
      # Also c/cpp -> clangtidy, same reasoning: clangd with `--clang-tidy` (§2.1).
      # c = [ "clangtidy" ];
      # cpp = [ "clangtidy" ];
    };

    # Lint on `:w` (nixvim's default autocmd: BufWritePost -> require('lint').try_lint()).
    # Set to `null` for manual-only linting with `:Lint <name>`.
    # Per-linter tuning lives under `plugins.lint.linters.<name>`
    # (cmd/args/stdin/append_fname/stream/env/ignore_exitcode/parser), e.g.
    #   plugins.lint.linters.deadnix.args = [ --no-cleanup ];
    # (shellcheck is not one of them any more - it runs inside bashls, so its extra
    #  arguments are `plugins.lsp.servers.bashls.settings.shellcheckArguments`.)
  };
}
