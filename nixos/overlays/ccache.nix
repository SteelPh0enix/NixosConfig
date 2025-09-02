{ cacheDir, ... }:
(self: super: {
  ccacheWrapper = super.ccacheWrapper.override {
    extraConfig = ''
      export CCACHE_COMPRESS=1
      export CCACHE_DIR="${cacheDir}"
      export CCACHE_UMASK=007
      export CCACHE_SLOPPINESS=random_seed
      export HOME="$TMPDIR"
      echo "ccache dir: $CCACHE_DIR"
      if [ ! -d "$CCACHE_DIR" ]; then
        echo "====="
        echo "Directory '$CCACHE_DIR' does not exist"
        echo "Please create it with:"
        echo "  sudo mkdir -m0770 '$CCACHE_DIR'"
        echo "  sudo chown root:nixbld '$CCACHE_DIR'"
        echo "====="
        exit 1
      fi
      if [ ! -w "$CCACHE_DIR" ]; then
        echo "====="
        echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami)"
        echo "Please verify its access permissions"
        echo "====="
        exit 1
      fi
    '';
  };
})
