// ---------------------------------------------------------------------------
// Compile order for xrun.  Paths are relative to sim/xcelium, so run the build
// from this directory (the Makefile does).
// ---------------------------------------------------------------------------

// include search path for tb_classes.svh and everything it pulls in
-incdir ../../tb

// RTL
../../rtl/l1_cache_pkg.sv
../../rtl/sram_macro.sv
../../rtl/l1_cache_core.sv
../../rtl/l1_cache_top.sv

// TB
../../tb/l1_cache_if.sv
../../tb/env/l1_cache_fsm_cov.sv
../../tb/tb_top.sv
