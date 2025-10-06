# Hi! This is a quick intro to this setup

This machine is running NixOS.
You can find it's current configuration here: [https://github.com/SteelPh0enix/NixosConfig/tree/framework-pc]
I'll review pull requests if any features are required. Or just ask me to add/configure stuff.

**IMPORTANT: My network connection is *relatively slow*, but stable. Please do not start any big downloads without my knowledge, as they may get killed if i notice them :)**

## Shell

To see list of already installed packages, look here: [https://github.com/SteelPh0enix/NixosConfig/blob/framework-pc/nixos/packages.nix#L55]
I've also configured `,` command to run any program from `nixpkgs`.
You can search for the packages here: [https://search.nixos.org/packages], or just try running the executable with `,` prefix if it's not installed, for example:

```sh
, htop
```

I've pre-installed my shell aliases and functions in your `~/.config/fish` directory.
Most will work, but you don't have `sudo` permissions (unless you explicitly ask for them :)), so some may not.

Some developer-related stuff (GCC/Clang/cargo+rust/uv) is installed globally and regularly updated.
Other than that, you can use docker and/or Nix.
I do not have rootless docker set up, but you should be added to `docker` group.
Direnv is also installed and set up.

## LLMs

Shared model files are stored in /home/LLMs directory, and it's read-only for all users in `users` group.
Recommended way of running the models is `llama-server`.
Aliases for running shared models are provided in ~/.config/fish/functions.
You should also have generic aliases for `llama-server` from global fish config: `serve-llm`, `serve-llm-jinja` and `serve-llm-jinja-ext`.
Try using them without arguments to see what they need.
Run `llama-server --help` for full list of arguments.

By default, `llama-server` will run on port 51536 of all interfaces.

There's also OpenWebUI running on port 55569, you need to "register" there to use it, but you can enter dummy email, i'm not sending anything there, nor using it anywhere.
It's purely for user identification for session storage purposes.

Other than that, you may try running ollama after installing it locally, but i generally don't recommend it - CPU inference is relatively slow, and ROCm is currently bugged as fuck.
ROCm basically cannot handle the memory on this APU and refuses to allocate anything above 32GB, while Vulkan has no issues grabbing the whole 120GB if necessary.
Do not trust `btop` and other resource monitors, RAM is shared between GPU and CPU so even if software shows you that GPU memory is filled, it can still use RAM via GTT.
I've set it to have up to 120GB of system memory, 8GB should always be left for the CPU.
**Please do not try loading models that require more than 120GB memory, as it will halt the system. When working with big models, start with small context sizes.** I've enabled `watchdogd` so it *should* reboot after a while, but... y'know.

## DNS

This machine runs PiHole. You can set it up as your DNS and enjoy ad filtering.
The requests are logged for diagnostic and statistics purposes only, i usually don't look at them unless they are in top 10.
