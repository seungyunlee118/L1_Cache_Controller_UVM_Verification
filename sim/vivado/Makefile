# ============================================================================
#  L1 cache UVM testbench - Vivado xsim   (Linux / macOS / WSL / Git-Bash)
#
#    make                                  # compile + elab + run default test
#    make TEST=l1_cache_stress_test SEED=42
#    make regress                          # all tests x seeds + merged coverage
#    make cov                              # print the merged coverage summary
#    make wave                             # rebuild with VCD dumping enabled
#    make clean
#
#  Tool discovery: if xvlog is on PATH (you sourced settings64.sh) it is used
#  as-is; otherwise setup_env.sh locates Vivado. Point it at your install with
#    export VIVADO_ROOT=/opt/Xilinx/Vivado/2025.2
#
#  Paths in files.f are relative to this directory, so always run make from
#  sim/vivado (or `make -C sim/vivado ...`).
# ============================================================================

SHELL := /bin/bash
.ONESHELL:

TEST  ?= l1_cache_random_test
SEED  ?= 1
SNAP  := l1_cache_tb

TESTS := l1_cache_smoke_test l1_cache_random_test l1_cache_thrash_test \
         l1_cache_eviction_test l1_cache_b2b_test l1_cache_line_test \
         l1_cache_be_test l1_cache_stress_test l1_cache_passive_test \
         l1_cache_reset_test l1_cache_reset_async_test
SEEDS := 1 7 42 999

XVLOG_OPTS := -sv -L uvm -f files.f
XELAB_OPTS := -L uvm -relax -timescale 1ns/1ps
REPORT     := xsim_coverage_report/functionalCoverageReport/xcrg_func_cov_report.txt

.PHONY: all sim compile elab run regress cov wave clean help

all: run

# ---- build steps -----------------------------------------------------------
compile:
	source ./setup_env.sh
	xvlog $(XVLOG_OPTS) -log xvlog.log

elab: compile
	source ./setup_env.sh
	xelab $(XELAB_OPTS) -s $(SNAP) tb_top -log xelab.log

# VCD-enabled build (opens dump.vcd during the run)
wave:
	source ./setup_env.sh
	xvlog $(XVLOG_OPTS) -log xvlog.log
	xelab $(XELAB_OPTS) -d DUMP_VCD -s $(SNAP) tb_top -log xelab.log
	xsim $(SNAP) -R -sv_seed $(SEED) -testplusarg "UVM_TESTNAME=$(TEST)" -log xsim.log

# ---- single run ------------------------------------------------------------
run sim: elab
	source ./setup_env.sh
	xsim $(SNAP) -R -sv_seed $(SEED) -testplusarg "UVM_TESTNAME=$(TEST)" -log xsim.log
	echo
	echo "=== RESULT ============================================"
	grep -E "SCOREBOARD SUMMARY|CPU reads|hits / misses|Dirty evictions|Way utilisation|Set reach|Resets / poisoned|cache_ops covergroup|FSM COV|UVM_ERROR :|UVM_FATAL :" xsim.log || true

# ---- full regression + merged coverage -------------------------------------
regress:
	source ./setup_env.sh
	rm -rf xsim.covdb xsim_coverage_report
	xvlog $(XVLOG_OPTS) -log xvlog.log
	xelab $(XELAB_OPTS) -s $(SNAP) tb_top -log xelab.log
	failed=0
	echo
	echo "==================== REGRESSION ===================="
	for t in $(TESTS); do
	  for s in $(SEEDS); do
	    log="regr_$${t}_$${s}.log"
	    xsim $(SNAP) -R -sv_seed $$s -testplusarg "UVM_TESTNAME=$$t" \
	         -cov_db_name "$${t}_$${s}" -log "$$log" >/dev/null 2>&1
	    if grep -qE "UVM_ERROR :[[:space:]]+0[[:space:]]*$$" "$$log" \
	       && grep -qE "UVM_FATAL :[[:space:]]+0[[:space:]]*$$" "$$log"; then
	      cov=$$(grep -oE "FUNCCOV=[0-9.]+" "$$log" | cut -d= -f2)
	      printf "  pass  %-28s seed=%-4s funccov=%s%%\n" "$$t" "$$s" "$$cov"
	    else
	      echo "  FAIL  $$t  seed=$$s"
	      failed=$$((failed+1))
	    fi
	  done
	done
	echo "===================================================="
	if [ $$failed -ne 0 ]; then
	  echo "REGRESSION FAILED: $$failed run(s)"
	  exit 1
	fi
	echo "REGRESSION PASSED"
	echo
	echo "==================== MERGED COVERAGE ================"
	xcrg -merge_db_name merged -report_format text -log xcrg.log >/dev/null 2>&1
	score=$$(grep -E "Coverage Score" "$(REPORT)" | head -1 | grep -oE "[0-9]+" | head -1)
	echo "  merged functional coverage : $${score}%"
	echo "  report: $(REPORT)"
	echo "===================================================="

# ---- print the merged coverage report (after a regress) --------------------
cov:
	if [ ! -f "$(REPORT)" ]; then
	  echo "No coverage report yet - run 'make regress' first."
	  exit 1
	fi
	sed -n '1,40p' "$(REPORT)"

# ---- housekeeping ----------------------------------------------------------
clean:
	rm -rf xsim.dir xsim.covdb xsim.codeCov xsim_coverage_report .Xil
	rm -f  *.log *.pb *.jou *.wdb *.vcd webtalk* tr_db.log
	echo "cleaned."

help:
	@echo "targets: run (default) | regress | cov | wave | clean"
	@echo "vars:    TEST=<name>  SEED=<n>   (e.g. make TEST=l1_cache_be_test SEED=7)"
	@echo "tests:   $(TESTS)"
