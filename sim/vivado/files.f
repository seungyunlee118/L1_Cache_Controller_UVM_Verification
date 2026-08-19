// ---------------------------------------------------------------------------
// Compile order for xvlog.  Paths are relative to sim/vivado, so run the build
// from this directory (Makefile / run.sh / run.bat all do).
// ---------------------------------------------------------------------------

// include search path for tb_classes.svh and everything it pulls in
-i ../../tb

// RTL
../../rtl/l1_cache_pkg.sv
../../rtl/sram_macro.sv
../../rtl/l1_cache_core.sv
../../rtl/l1_cache_top.sv

// TB
../../tb/l1_cache_if.sv
../../tb/env/l1_cache_fsm_cov.sv
../../tb/tb_top.sv
