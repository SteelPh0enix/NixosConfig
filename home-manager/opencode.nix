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
          "git commit *" = "ask";
          "git push *" = "deny";
          "git status *" = "allow";
          "yarn build *" = "allow";
          "yarn test *" = "allow";
          "yarn lint *" = "allow";
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
        options.baseURL = "http://192.168.0.185:51536/v1";
        models = {
          "glm-flash" = {
            name = "GLM Flash";
            limit = {
              context = 202752;
              output = 65536;
            };
          };
          "qwen-coder" = {
            name = "Qwen Coder";
            limit = {
              context = 262144;
              output = 65536;
            };
          };
        };
      };
    };
  };
}
