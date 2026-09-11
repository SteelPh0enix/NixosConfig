{ ... }:
{
  # Polkit prompts (pkexec, gparted, removable media). Noctalia has its own agent
  # (`shell.polkit_agent`) but its docs say to leave it off when another agent handles prompts,
  # and hyprpolkitagent is the one the Hyprland ecosystem expects.
  services.hyprpolkitagent.enable = true;
}
