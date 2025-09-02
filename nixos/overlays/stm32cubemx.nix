(self: super: {
  stm32cubemx = super.stm32cubemx.overrideAttrs (old: {
    src = super.fetchzip {
      url = "https://sw-center.st.com/packs/resource/library/stm32cube_mx_v6150-lin.zip";
      hash = "e10f578e1e4f161283b938dfb3fd50af";
      stripRoot = false;
    };
  });
})
