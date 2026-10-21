# ============================================================================
#  L1 cache UVM testbench - Cadence Xcelium (xrun)
#
#    make                                   # build + run the default test
#    make TEST=l1_cache_stress_test SEED=42
#    make XPROP=C                           # X-propagation build (C or F)
#    make WAVE=1                            # dump an SHM database -> waves.shm
#    make view                              # open waves.shm in SimVision (view.tcl layout)
#    make GUI=1                             # open the run in SimVision
#    make regress                           # 11 tests x 4 seeds  (regress.sh)
#    make regress_xprop                     # the same with -xprop C
#    make mutate                            # bug-injection campaign (mutate.py)
#    make clean
#
#  Runtime knobs pass straight through: make PLUSARGS="+NUM_TRANS=500 +SEQ=l1_cache_rand_seq"
# ============================================================================

SHELL := /bin/bash

TEST     ?= l1_cache_random_test
SEED     ?= 1
XPROP    ?=
WAVE     ?= 0
GUI      ?= 0
PLUSARGS ?=

LIBDIR := xcelium$(if $(XPROP),_xprop$(XPROP)).d

RUN_OPTS := -F xrun.args -F files.f -xmlibdirname $(LIBDIR) \
            -covtest $(TEST)_$(SEED) -svseed $(SEED) +UVM_TESTNAME=$(TEST) $(PLUSARGS)
ifneq ($(XPROP),)
RUN_OPTS += -xprop $(XPROP)
endif
ifeq ($(WAVE),1)
RUN_OPTS += -access +r -input waves.tcl
endif
ifeq ($(GUI),1)
RUN_OPTS += -access +rwc -gui
endif

.PHONY: all run view regress regress_xprop mutate clean help

all: run

# Exits non-zero when the run fails the same rule regress.sh uses (judge.sh),
# so `make && ...` stops on a broken test. xrun's own exit code is not used:
# it is 1 on the lab host for every run because of the known IMPDLL message.
run:
	@source ./xcelium_env.sh && source ./judge.sh && xrun $(RUN_OPTS) -l xrun.log > /dev/null; \
	echo; echo "=== RESULT ($(TEST), seed $(SEED)) ==="; \
	grep -E "SCOREBOARD SUMMARY|Architectural reads|CPU reads|hits / misses|Dirty evictions|Way utilisation|Set reach|Resets / poisoned|cache_ops covergroup|FSM COV|SVA COVER|UVM_ERROR :|UVM_FATAL :" xrun.log; \
	grep -E "^UVM_(ERROR|FATAL) .* @ " xrun.log | head -5; \
	verdict=$$(judge xrun.log); echo "=== $$verdict ==="; [ "$${verdict%% *}" = PASS ]

# Plain `simvision` starts the 32-bit binary, which needs the 32-bit libX11 the
# lab host does not have; -64bit picks the 64-bit one. view.tcl lays out the
# CPU, controller and memory signals so the window does not open empty.
view:
	@source ./xcelium_env.sh && simvision -64bit waves.shm -input view.tcl &

regress:
	./regress.sh

regress_xprop:
	./regress.sh -x C -o regress_xprop

mutate:
	python3 mutate.py

clean:
	rm -rf xcelium*.d cov_work regress regress_xprop mutants waves.shm .simvision
	rm -f *.log *.history *.key *.diag xmsim.* .reinvoke.sim
	@echo cleaned.

help:
	@sed -n '2,16p' Makefile
