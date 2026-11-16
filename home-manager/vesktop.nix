{ lib, ... }:
let
  # Vencord keys plugin settings by the `name` field of the plugin definition, not the directory
  # name, so these are PascalCase (shikiCodeblocks.desktop -> ShikiCodeblocks).
  enabledPlugins = [
    "AnonymiseFileNames"
    "AutoDNDWhilePlaying"
    "BetterSessions"
    "CrashHandler"
    "BiggerStreamPreview"
    "CallTimer"
    "DisableCallIdle"
    "UserVoiceShow"
    "VoiceChatDoubleClick"
    "VoiceMessages"
    "VolumeBooster"
    "AddAttachments"
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
    "QuickReply"
    "ReadAllNotificationsButton"
    "ReplyTimestamp"
    "SendTimestamps"
    "TypingIndicator"
    "TypingTweaks"
    "WhoReacted"
    "BetterFolders"
    "MentionAvatars"
    "BetterRoleDot"
    "ShowConnections"
    "UserMessagesPronouns"
    "Dearrow"
    "FixImagesQuality"
    "FixSpotifyEmbeds"
    "FixYoutubeEmbeds"
    "ImageFilename"
    "ImageZoom"
    "MessageLinkEmbeds"
    "OpenInApp"
    "TenorGifSearch"
    "YoutubeAdblock"
    "FixCodeblockGap"
    "ShikiCodeblocks"
    "TextReplace"
    "Translate"
    "Unindent"
    "ValidUser"
    "ConsoleJanitor"
    "NoF1"
  ];
in
{
  # Vencord rewrites settings.json on every toggle made in its own UI, so re-apply home-manager
  # after experimenting to get the declared state back.
  programs.vesktop = {
    enable = true;

    # nixpkgs' vencord instead of letting Vesktop fetch its own copy into ~/.local/share.
    vencord.useSystem = true;

    settings = {
      discordBranch = "stable";

      staticTitle = true;
      enableMenu = false;
      disableMinSize = true;
      disableSmoothScroll = false;

      tray = true;
      minimizeToTray = false;
      clickTrayToShowHide = true;
      appBadge = false;
      enableTaskbarFlashing = false;

      hardwareAcceleration = true;
      hardwareVideoAcceleration = false;

      arRPC = true;

      webRTCIPHandlingPolicy = "default_public_interface_only";
      spellCheckLanguages = [
        "en"
        "pl"
      ];

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
      cloud.settingsSync = false;

      notifications = {
        timeout = 5000;
        position = "bottom-right";
        useNative = "not-focused";
      };

      enabledThemes = [ "noctalia-material.theme.css" ];

      plugins = lib.genAttrs enabledPlugins (_: {
        enabled = true;
      });
    };
  };
}
