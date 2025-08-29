self: super: {
  llama-cpp-rocm = super.llama-cpp-rocm.override {
    rocmSupport = true;
    rocmPackages = with pkgs.rocmPackages; [
      amdsmi
      aotriton
      clang
      clr
      composable_kernel
      half
      hip-common
      hipblas
      hipblas-common
      hipblaslt
      hipcc
      hipfft
      hipify
      hiprand
      hiprt
      hipsolver
      hipsparse
      hsakmt
      llvm.bintools
      llvm.clang-tools
      llvm.compiler-rt
      llvm.libcxx
      llvm.lld
      llvm.llvm
      llvm.openmp
      migraphx
      miopen
      mpi
      rccl
      rocalution
      rocblas
      rocfft
      rocm-bandwidth-test
      rocm-cmake
      rocm-comgr
      rocm-core
      rocm-device-libs
      rocm-smi
      rocmPath
      rocmilr
      rocminfo
      rocprim
      rocrand
      rocsparse
      rocthrust
      rocwmma
      triton
      triton-llvm
    ];
    rocmGpuTargets = "gfx1100";
  };
}
