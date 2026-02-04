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
          "MiniMax-M2.1" = {
            name = "MiniMax-M2.1";
            limit = {
              context = 81920;
              output = 65536;
            };
          };
          "GLM-4.5-Air" = {
            name = "GLM-4.5-Air";
            limit = {
              context = 131072;
              output = 65536;
            };
          };
          "GLM-4.7-Flash" = {
            name = "GLM-4.7-Flash";
            limit = {
              context = 202752;
              output = 65536;
            };
          };
          "Qwen-Coder-30B" = {
            name = "Qwen-Coder-30B";
            limit = {
              context = 131072;
              output = 65536;
            };
          };
          "Qwen3-Next" = {
            name = "Qwen3-Next";
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
