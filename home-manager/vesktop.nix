{ lib, ... }:
let
  # Vencord keys plugin settings by the `name` field of the plugin definition, not by the directory
  # name, so these are PascalCase (shikiCodeblocks.desktop -> ShikiCodeblocks).
  enabledPlugins = [
    # Presence, accounts and uploads
    "AnonymiseFileNames" # randomise the name of every uploaded file
    "AutoDNDWhilePlaying" # status follows the game you launch
    "BetterSessions" # exact timestamps, custom names and new-login notifications in the device list
    "CrashHandler" # recover a crashed renderer instead of restarting the whole app
    # Voice and streaming
    "BiggerStreamPreview"
    "CallTimer"
    "DisableCallIdle" # stay in DM calls past the 3 minute kick and out of AFK channels
    "UserVoiceShow"
    "VoiceChatDoubleClick"
    "VoiceMessages"
    "VolumeBooster"
    # Chat
    "AddAttachments" # attach files while editing a message
    "CharacterCounter"
    "ClearURLs" # strips tracking parameters from the links you send
    "FullSearchContext"
    "ImplicitRelationships"
    "MemberCount"
    "MessageClickActions" # double click edits, backspace + click deletes
    "MessageLatency"
    "NoBlockedMessages" # blocked users' messages are dropped instead of collapsed
    "NoPendingCount" # drops the ping count on friend/msg requests and nitro offers
    "PreviewMessage"
    "QuickMention"
    "QuickReply" # ctrl+up/down reply, ctrl+shift+up/down edit
    "ReadAllNotificationsButton"
    "ReplyTimestamp"
    "SendTimestamps"
    "TypingIndicator"
    "TypingTweaks" # avatars and role colours inside the indicator
    "WhoReacted"
    # Appearance
    "BetterFolders"
    "MentionAvatars"
    "BetterRoleDot"
    "ShowConnections"
    "UserMessagesPronouns"
    # Media, embeds and links
    "Dearrow" # de-sensationalised YouTube embed titles and thumbnails
    "FixImagesQuality"
    "FixSpotifyEmbeds" # volume slider for the autoplaying embed
    "FixYoutubeEmbeds"
    "ImageFilename"
    "ImageZoom"
    "MessageLinkEmbeds"
    "OpenInApp"
    "TenorGifSearch"
    "YoutubeAdblock"
    # Text and code
    "FixCodeblockGap"
    "ShikiCodeblocks"
    "TextReplace"
    "Translate"
    "Unindent"
    "ValidUser" # repairs mentions that render as @unknown-user
    # Console
    "ConsoleJanitor" # silences Discord's console spam
    "NoF1" # frees the F1 help binding
  ];
in
{
  # Replaces the proprietary discord package: GPL-3 build from source, Vencord preinstalled,
  # PipeWire screen share with system audio. Its desktop entry claims x-scheme-handler/discord.
  # Vencord rewrites settings.json on every toggle made in its own UI, so re-apply home-manager
  # after experimenting to get the declared state back.
  programs.vesktop = {
    enable = true;

    # Use nixpkgs' vencord (built with --disable-updater) instead of letting Vesktop fetch its own
    # copy into ~/.local/share on first start; the plugin set then moves with nixpkgs.
    vencord.useSystem = true;

    settings = {
      discordBranch = "stable";

      staticTitle = true; # one stable window title for the Hyprland rules
      enableMenu = false;
      disableMinSize = true;
      disableSmoothScroll = false;

      tray = true;
      minimizeToTray = false;
      clickTrayToShowHide = true;
      appBadge = false; # the noctalia tray draws no unread badge
      enableTaskbarFlashing = false; # no taskbar to flash

      hardwareAcceleration = true;
      hardwareVideoAcceleration = false; # can hang streams on some GPUs

      arRPC = true; # Rich Presence; the arrpc server is built into Vesktop, no service needed

      webRTCIPHandlingPolicy = "default_public_interface_only"; # keeps the LAN address out of calls
      spellCheckLanguages = [
        "en"
        "pl"
      ];

      # Screen share: venmic routes system audio through an extra playback sink (workaround), and
      # the picker gets the full device list instead of only the default speakers.
      audio = {
        workaround = true;
        deviceSelect = true;
        granularSelect = true;
        ignoreVirtual = false;
        ignoreDevices = false;
        ignoreInputMedia = false;
        onlySpeakers = true;
        onlyDefaultSpeakers = true;
      };
    };

    # eagerPatches deliberately unset: patching during webpack init hits a TDZ error inside Discord's
    # bundle ("Cannot access 'xx' before initialization") and leaves the window white.
    vencord.settings = {
      autoUpdate = false;
      autoUpdateNotification = false;
      disableMinSize = true;
      cloud.settingsSync = false; # would fight the declarative settings

      notifications = {
        timeout = 5000;
        position = "bottom-right";
        useNative = "not-focused"; # libnotify, so noctalia handles the popups
      };

      # Noctalia's community "discord" template renders exactly this file
      # (~/.config/vesktop/themes/noctalia.theme.css). Until it exists, Discord's own dark theme stays.
      enabledThemes = [ "noctalia.theme.css" ];

      plugins = lib.genAttrs enabledPlugins (_: { enabled = true; });
    };
  };
}
