(self: super: {
  freecad = super.freecad.override {
    withWayland = true;
    qtVersion = 6;
  };
})
