{
  pkgs,
  nix-ai-tools,
  ...
}:
{
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    web.enable = false;

    context = ''
      ## General guidelines

      - When searching for files, ALWAYS use `fd` (fdfind) instead of default `find`.
      - When searching for text, ALWAYS use `rg` (ripgrep) instead of default grep.
      - ALWAYS ground your research by searching the web with Kagi.
    '';

    agents = {
      docs-writer = ./opencode-agents/docs-writer.md;
      reviewer = ./opencode-agents/reviewer.md;
      security-auditor = ./opencode-agents/security-auditor.md;
      tester = ./opencode-agents/tester.md;
    };

    tui = {
      diff_style = "auto";
    };

    settings = {
      server = {
        hostname = "localhost";
        mdns = false;
      };

      tools = {
        bash = true;
        edit = true;
        write = true;
        read = true;
        grep = true;
        glob = true;
        list = true;
        lsp = true;
        patch = true;
        skill = true;
        todowrite = true;
        todoread = true;
        webfetch = true;
        question = true;
      };

      permission = {
        bash = {
          "*" = "ask";
          "grep *" = "allow";
          "rg *" = "allow";
          "ls *" = "allow";
          "fd *" = "allow";
          "fd * -x *" = "ask";
          "fd * | *" = "ask";
          "git commit *" = "ask";
          "git push *" = "deny";
          "git status *" = "allow";
          "yarn build *" = "allow";
          "yarn test *" = "allow";
          "yarn lint *" = "allow";
          "uv run *" = "allow";
          "uv tree *" = "allow";
          "uv build *" = "allow";
          "uv tool *" = "allow";
          "uv help *" = "allow";
          "uv format *" = "allow";
        };
        read = {
          "*.md" = "allow";
          "*.ts" = "allow";
          "*.js" = "allow";
          "*.mjs" = "allow";
          "*.c" = "allow";
          "*.cpp" = "allow";
          "*.h" = "allow";
          "*.hpp" = "allow";
          "CMakeLists.txt" = "allow";
          "SCons*" = "allow";
          "*.py" = "allow";
          "Jenkinsfile" = "allow";
          "*.yml" = "allow";
        };
        grep = {
          "*" = "allow";
        };
        list = {
          "*" = "allow";
        };
      };

      default_agent = "plan";
      share = "disabled";
      autoupdate = false;

      plugin = [
        "@nick-vi/opencode-type-inject"
        "@franlol/opencode-md-table-formatter"
        "@zenobius/opencode-skillful"
      ];

      enabled_providers = [
        "llama.cpp"
        "moonshotai"
        "nvidia"
        "novita-ai"
        "openrouter"
      ];

      mcp = {};

      provider."llama.cpp" = {
        npm = "@ai-sdk/openai-compatible";
        name = "llama-server (local)";
        options.baseURL = "http://steelph0enix.framework:51536/v1";
        models = {
          "coder-reasoning" = {
            name = "Default coding model";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "coder-smart-reasoning" = {
            name = "Smarter coding model";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "coder" = {
            name = "Default coding model (reasoning off)";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "coder-smart" = {
            name = "Smarter coding model (reasoning off)";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "nvidia-nemotron-3-super" = {
            name = "Fuck it we ball";
            limit = {
              context = 1048576;
              output = 102400;
            };
          };
          "deepseek-v4-flash" = {
            name = "Deepseek V4 Flash";
            limit = {
              context = 256000;
              output = 32768;
            };
          };
        };
      };
    };
  };
}
