(self: super: {
  vllm-fpc = super.vllm.override {
    rocmSupport = true;
  };
})
