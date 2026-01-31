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
    settings = {
      tui = {
        diff_style = "auto";
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
      };

      enabled_providers = [
        "llama.cpp"
        "moonshot.ai"
      ];

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
          "Devstral-2" = {
            name = "Devstral-2";
            limit = {
              context = 262144;
              output = 131072;
            };
          };
        };
      };
    };
    rules = ''
      # General rules

      - Try to be concise in your responses, reduce unnecessary yapping to minimum, but if you believe something is relatively important, include it in the response.
      - If you're unsure about something, or you lack information/resources to confirm something, you ALWAYS MUST tell that to the user. ALWAYS back your responses with specific data and knowledge.
      - DO NOT add redundant/unnecessary comments to the code. Only add comments when necessary, for example, if a piece of code would be hard to understand otherwise or requires additional context for understanding it's purpose. However, even in that case, it's usually better to separate that piece of code into a function or something similar.
      - ALWAYS add documentation to the code, if the language doesn't provide a standardized way of doing that, assume Doxygen format.

      ## C language specific rules

      - If the language standard is not explicitly mentioned, assume C23

      ## C++ language specific rules

      - If the language standard is not explicitly mentioned, assume C++23

      ## Python specific rules

      - If the interpreted version is not explicitly mentioned, assume cPython 3.14
      - Use `uv` for managing the project, never use `pip` directly - only via `uv pip`.
      - Always use virtual environments for Python projects. If there's no virtualenv in the project, create and enable one before proceeding.
    '';
    agents = {
      review = ''
        ---
        description: Reviews code for quality and best practices
        mode: subagent
        tools:
          write: false
          edit: false
          bash: false
        ---

        You are in code review mode. Focus on:

        - Code quality and best practices
        - Potential bugs and edge cases
        - Performance implications
        - Security considerations

        Provide constructive feedback without making direct changes.
      '';
      docs-writer = ''
        ---
        description: Writes and maintains project documentation
        mode: subagent
        tools:
          bash: false
        ---

        You are a technical writer. Create clear, comprehensive documentation.

        Focus on:

        - Clear explanations
        - Proper structure
        - Code examples
        - User-friendly language
      '';
      security-auditor = ''
        ---
        description: Performs security audits and identifies vulnerabilities
        mode: subagent
        tools:
          write: false
          edit: false
        ---

        You are a security expert. Focus on identifying potential security issues.

        Look for:

        - Input validation vulnerabilities
        - Authentication and authorization flaws
        - Data exposure risks
        - Dependency vulnerabilities
        - Configuration security issues
      '';
    };
  };
}
