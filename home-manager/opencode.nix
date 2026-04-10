{
  pkgs,
  nix-ai-tools,
  ...
}:
{
  xdg.configFile."opencode/agents".source = ./opencode-agents;

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    package = nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    settings = {
      tui = {
        diff_style = "auto";
      };

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

      mcp = {
        searxng = {
          type = "local";
          enabled = true;
          command = [
            "npx"
            "-y"
            "mcp-searxng"
          ];
          environment = {
            "SEARXNG_URL" = "https://search.steelph0enix.dev/";
          };
        };
      };

      provider."llama.cpp" = {
        npm = "@ai-sdk/openai-compatible";
        name = "llama-server (local)";
        options.baseURL = "http://steelph0enix.framework:51536/v1";
        models = {
          "coder" = {
            name = "Default coding model";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "coder-smart" = {
            name = "Smarter (but slower) coding model";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "quick" = {
            name = "Quick model for simple tasks";
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
          "qwen-dense-coder" = {
            name = "Smarter (but slower) coding Qwen model";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "gemma-dense" = {
            name = "Gemma 4 31B";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
          "gemma-moe" = {
            name = "Gemma 4 26B A4B";
            limit = {
              context = 262144;
              output = 32768;
            };
          };
        };
      };
    };
  };
}
