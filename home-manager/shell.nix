{
  xdg.configFile."fish/config.fish".source = ./config.fish;

  # Fish autoloads functions from ~/.config/fish/functions/<name>.fish.
  xdg.configFile."fish/functions/remote-cp.fish".source = ./fish/functions/remote-cp.fish;
  xdg.configFile."fish/functions/llm-router.fish".source = ./fish/functions/llm-router.fish;
}
