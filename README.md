# Pipelined L1 Cache Controller — UVM Verification

4-way set associative, write-back / write-allocate L1 data cache with a 2-stage
pipeline, tree-PLRU replacement, 16-byte lines filled and evicted as bursts, and
byte-enable writes.

Verified with a UVM testbench: golden cache reference model, constrained-random
stimulus, a reactive burst memory responder with variable latency and
backpressure on both channels, a reset agent, SVA, and functional + white-box
FSM coverage merged across the regression.

Simulator: **Vivado xsim 2025.2** (built-in UVM 1.2).

> 📐 구조 다이어그램: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
> 🎯 면접 대비 정리: [docs/INTERVIEW_PREP.md](docs/INTERVIEW_PREP.md)

```
regress.bat  ->  44/44 pass  (11 tests x 4 seeds)
                 UVM_ERROR 0, UVM_FATAL 0, SVA failures 0
                 merged functional coverage : 100%
                 FSM coverage               : 100% (stress test), >=97.5% elsewhere
```

---

## 1. Architecture

```
        S1                                S2
   ┌───────────┐                    ┌──────────────────┐
   │ CPU req   │  set index ───────▶│ 4x tag SRAM      │──▶ 4-way compare ──▶ hit/way
   │ valid/rw  │  {set,word} ──────▶│ 4x data SRAM     │──▶ way mux ────────▶ rdata
   │ addr/be   │                    └──────────────────┘
   │ wdata     │                    valid/dirty/PLRU in flops
   └───────────┘   pipeline reg (holds while stalled)
        ▲
   cpu_req_ready = ~pipeline_stall
```

| | |
|---|---|
| Organisation | 4-way set associative |
| Sets / ways | 64 sets x 4 ways = 256 lines |
| Line size | 4 words (16 B) → 4 KB total |
| Policy | write-back, write-allocate |
| Replacement | tree-PLRU (3 bits/set), invalid ways filled first |
| Writes | byte enables (`cpu_req_be[3:0]`) |
| Address split | `tag = addr[31:10]`, `set = addr[9:4]`, `word = addr[3:2]`, `byte = addr[1:0]` |
| Array model | registered read port (address in cycle N → data in cycle N+1) |
| Memory | burst: request + separate write-data and read-data channels, 4 beats |
| Latency | read hit = 1 cycle; miss = fill (+ write-back if the victim is dirty) |

The address split lives in **one place** — `get_set()` / `get_tag()` /
`get_word()` / `make_line_addr()` in `rtl/l1_cache_pkg.sv` — and both the RTL and
the testbench use those helpers, so the two can never drift apart.

### FSM

```
  ST_IDLE ──miss, clean victim──────────────────────▶ ST_FILL_REQ
     │                                                     │
     └─miss, dirty victim──▶ ST_WB_READ ──▶ ST_WB_SEND ────┘
                            (buffer line)   (stream out)   │
                                                           ▼
                                                     ST_FILL_RCV
                                                           │
                                                           ▼
        ST_IDLE ◀────────────────────────────────── ST_COMPLETE
```

Each state has exactly one job. `ST_COMPLETE` costs one extra cycle per miss
but removes the structural conflict between the last fill beat and the pending
store's write, and it is where the tag, valid/dirty and PLRU are committed.
Stall is released in `ST_COMPLETE` so the pipeline advances at the end of that
cycle — otherwise S2 would still hold the request in `ST_IDLE` next cycle and
answer it a second time.

### Three things worth understanding

**Registered array reads + read-during-write forwarding.**
The array read port samples memory *before* the write of that same edge lands.
If the previous cycle wrote the location being read, the core forwards the write
data around the array. The comparison is against the address actually issued
last cycle (`prev_*_raddr`), not against S2 — during `ST_WB_READ` the read
address walks the line and is not `s2_word`. Data forwarding is **per byte**,
because a store may have written only some lanes.

**Why there is no combinational loop.**
`tag_raddr` is selected using `pipeline_stall`, but `tag_rdata` is a flop
output, so nothing downstream of the read feeds back into the stall. With a
combinational-read SRAM this same mux *does* close a loop:
`stall → raddr → rdata → hit → stall`.

**Valid/dirty/PLRU live in flops, not SRAM.**
Reset therefore flushes the entire cache in one cycle, with no power-on
invalidate walk and no need for non-synthesisable 4-state compares to cope with
an uninitialised tag array.

---

## 2. Testbench

```
tb_top
 ├─ bind l1_cache_fsm_cov -> l1_cache_core        (white-box FSM coverage)
 └─ l1_cache_env
     ├─ cpu_agt   sequencer + driver + monitor   ── req_ap ─┐
     │                                           ── rsp_ap ─┤
     ├─ mem_agt   sequencer + burst responder + monitor ────┤
     ├─ rst_agt   sequencer + reset driver       ── ap ─────┤
     ├─ scb       golden CACHE model  ◀──────────────────────┘
     └─ cov       functional coverage ◀── scb.cov_ap
```

### Golden cache model

The scoreboard mirrors the DUT's tag / valid / dirty / data arrays across all
four ways, the PLRU tree, and main memory. For every CPU request it predicts
hit or miss **and which way**, the exact data a read must return (byte-enable
accurate), whether the PLRU victim is dirty and must be written back — to which
address, with which four beats — and the fill burst that follows with the data
it must carry. Observed memory traffic is checked against that prediction **in
order**, so a spurious, missing, mis-addressed, mis-ordered or wrong-length
burst fails the test.

### Ordering

The CPU monitor publishes on **two** analysis ports: `req_ap` (every accepted
request, read and write, in issue order) and `rsp_ap` (read responses). The
expected value for a read is snapshot at **issue** time and checked at
**response** time. That matters because the DUT is pipelined: a read miss can
retire in the very same cycle the next request is accepted, so comparing
against the *current* reference state yields false failures.

### Memory responder

`l1_cache_mem_rsp_seq` feeds the memory driver one timing item per burst:
randomised fill latency, randomised request-channel backpressure, and
randomised gaps between beats. The stress test runs 10–50 cycle latency with
60% of bursts seeing up to 6 cycles of request backpressure and gaps on both
the write-data and read-data channels.

### Reset

The reset agent owns `rst_n`, performs the power-on reset, and can re-assert it
mid-traffic. It announces every reset on an analysis port so the scoreboard
flushes its model at exactly the same instant the DUT flushes its flops. Two
flavours:

* `l1_cache_reset_test` — the memory bus is allowed to go idle first, so
  nothing can be lost mid-burst and **every check stays live**.
* `l1_cache_reset_async_test` — reset fires at an arbitrary moment, including
  mid-burst. A write-back cut in half leaves DRAM in a state the model cannot
  reconstruct, so the scoreboard **poisons just those line addresses** and
  skips their data comparison. Every protocol, ordering and burst-length check
  stays active. In practice at most one line is poisoned per reset; the count
  is reported.

### Coverage

| | |
|---|---|
| `cache_ops` (subscriber) | rw, hit/miss, eviction, victim state (cold / clean / dirty), **way**, **word within line**, set reach, **byte-enable shape**, and 6 crosses |
| `cache_fsm` (bind into the core) | state, all legal transitions, `illegal_bins` on 12 illegal ones, stall-length buckets, backpressure on both memory channels, **fill beat position**, **victim way**, **hit way** |

Coverage is fed from the **scoreboard**, not the monitor — hit/miss, way and
victim state only exist in the reference model, not on the pins.

Assertions live in `tb/l1_cache_if.sv`: handshake hold, payload stability, X/Z
checks on every channel, line alignment, and **burst beat accounting** (each
burst must deliver exactly `len+1` beats with `LAST` on the final one).

> xsim ignores `cover property` (it prints `XSIM 43-4127` at elaboration).
> Those cover statements are still valid and collect in Questa.

---

## 3. Running

### Linux / macOS / WSL  (Makefile)

```bash
cd sim/vivado

# One-time: point at your Vivado install, or source it yourself.
export VIVADO_ROOT=/opt/Xilinx/Vivado/2025.2     # adjust to your path
#   (setup_env.sh also probes /tools/Xilinx/... and /opt/Xilinx/... automatically,
#    and does nothing if you already ran `source .../settings64.sh`)

make                                 # compile + elab + run default test
make TEST=l1_cache_stress_test SEED=42
make regress                         # all tests x 4 seeds + merged coverage
make cov                             # print the merged coverage summary
make wave                            # rebuild with VCD dumping, then run
make clean

# or the batch-file-style wrappers:
./run.sh l1_cache_be_test 7
./regress.sh
```

The tools are located by `setup_env.sh` (sourced automatically): it uses xsim
if it is already on `PATH`, else sources `$VIVADO_ROOT/settings64.sh`, else
probes common install locations. Vivado's precompiled UVM 1.2 is used via
`-L uvm` — nothing to compile yourself.

### WSL2 (fast native-filesystem build)

Vivado xsim I/O on the `/mnt/c` 9p mount is slow. Keep editing on Windows, but
build on the WSL2 native filesystem with the mirror helper — it rsyncs the
**source only** (no `xsim.dir`/logs) into `~/Pipelined_Cache_Cont` and runs make
there:

```bash
cd /mnt/c/Claud_work/Pipelined_Cache_Cont/sim/vivado
./wsl_local.sh                       # mirror + default test
./wsl_local.sh regress               # mirror + full regression
./wsl_local.sh TEST=l1_cache_be_test SEED=7
```

The `/mnt/c` copy stays the source of truth; `~/Pipelined_Cache_Cont` is a
throwaway build mirror (override with `export L1_WSL_DIR=~/somewhere`). Needs
`rsync` (`sudo apt-get install -y rsync`). Source Vivado / set `VIVADO_ROOT`
exactly as above — `setup_env.sh` runs inside the mirror too.

### Windows  (batch)

```bat
cd sim\vivado

run.bat                              :: default (l1_cache_random_test, seed 1)
run.bat l1_cache_stress_test 42      :: pick a test and a seed
regress.bat                          :: all tests x 4 seeds + merged coverage
```

Set `VIVADO_ROOT` if Vivado is not at `C:\AMDDesignTools\2025.2\Vivado`.

### Common to both

Runtime overrides: `+SEQ=<sequence>`, `+NUM_TRANS=<n>`, `+UVM_TESTNAME=<test>`.
Waveforms: `make wave` (or `xelab -d DUMP_VCD ...`).
Cache-internal trace: rebuild with `xelab -d CACHE_DEBUG ...`.

Merged coverage report after a regression:
`xsim_coverage_report/functionalCoverageReport/xcrg_func_cov_report.txt`

> **Line endings**: all HDL, filelists and shell scripts are committed as LF,
> enforced by `.gitattributes`. A shell script saved as CRLF fails on Linux with
> `bad interpreter: /bin/bash^M`; if you ever hit that, run
> `sed -i 's/\r$//' sim/vivado/*.sh`.

### Tests

| Test | Scenario | funccov |
|---|---|---|
| `l1_cache_smoke_test` | short sanity run, gentle memory | ~94% |
| `l1_cache_random_test` | mixed R/W over 8 tags per 4-way set (default) | 100% |
| `l1_cache_thrash_test` | whole-address-space random, everything misses | 83.9% |
| `l1_cache_eviction_test` | 6 tags per set — continuous PLRU eviction | 98.2% |
| `l1_cache_b2b_test` | true back-to-back, VALID never drops | 90.5% |
| `l1_cache_line_test` | multi-word line / spatial locality | ~79% |
| `l1_cache_be_test` | byte enables + per-byte forwarding | ~88% |
| `l1_cache_stress_test` | slow memory + heavy backpressure both channels | 100% |
| `l1_cache_passive_test` | passive CPU agent, BFM-driven stimulus | 57.1% |
| `l1_cache_reset_test` | mid-traffic reset, bus quiesced first | 100% |
| `l1_cache_reset_async_test` | reset at an arbitrary moment, incl. mid-burst | 100% |

Per-test numbers are low by design — each targets a narrow scenario. **The
merged number across the regression is 100%**, produced by `xcrg`.

---

## 4. History — what was wrong, and what changed

### RTL

| Fix | Detail |
|---|---|
| **Combinational loop removed** | `pipeline_stall → tag_raddr → tag_rdata → cache_hit → pipeline_stall` was a closed loop. Broken by making the array read port registered. |
| **SRAM read model** | `assign rdata = mem[raddr]` (combinational) contradicted the S1-addressed pipeline. Root cause of 675 read mismatches: on the allocate→hit turnaround the core read the *next* request's index and returned another line's data. |
| **Data-array forwarding added** | the tag array already had it; the data array needed the same, and now needs it **per byte**. |
| **Cache line geometry** | was `tag[31:12]/index[11:4]` (a 16-byte line) while the data array held one word per line, so `0x100` and `0x104` aliased onto the same tag+index. |
| **Direct-mapped → 4-way + PLRU** | one line per set meant any two hot addresses sharing an index thrashed permanently. |
| **1-word → 4-word lines, burst fill/evict** | the memory interface now carries real bursts with a beat count and `LAST`. |
| **Byte enables** | writes could only replace a whole word. |
| **Single-shot memory requests** | `mem_req_valid` stayed asserted for the whole allocate latency, so the memory model saw the same request repeatedly. |
| **Power-on flush** | the tag array powered up as X and hit/miss was decided with non-synthesisable `===`. valid/dirty now live in flops and reset clears them in one cycle. |
| **1-entry "vault" removed** | it forced `cache_hit=1` without checking the tag, so a read could hit on stale data after that line was evicted. It only existed to paper over the addressing bug. |
| **`always_comb` declaration initialisers** | `logic x = 0;` inside a procedural block is *static* — the initialiser runs once at time 0, not per evaluation. Rewritten as plain assignments. |

### Testbench

| Fix | Detail |
|---|---|
| **SVA failures were invisible to the regression** | assertions used `$error`, which does **not** increment `UVM_ERROR`, so a run with failing assertions still reported `UVM_ERROR : 0` and passed. They now call `uvm_report_error`, and this was confirmed with a deliberately-failing assertion (685 errors, run correctly flagged FAIL). |
| **Merged coverage exists after all** | an earlier note in this file claimed xsim cannot merge functional coverage. It can: `xsim -cov_db_name` per run, then `xcrg -merge_db_name`. Now wired into `regress.bat`. |
| **Golden model became a cache model** | the scoreboard modelled only main memory; it could not tell "this should have been a hit" from "this should have missed", nor predict which way, nor check fill data. |
| **Scoreboard ordering** | expected read data is snapshot at issue time. Was causing ~2 false failures per run. |
| **Functional coverage was dead code** | `l1_cache_coverage.sv` existed but was never included, built, connected or sampled — coverage was effectively 0%. |
| **Constrained randomisation** | every sequence assigned fields by hand (a workaround for a Questa FSE licence limit that no longer applies on xsim). |
| **Memory latency + backpressure** | the responder was hardwired zero-latency and permanently ready; `latency` was declared with a 10–50 cycle constraint that nothing used. |
| **Two dead assertions revived** | `p_valid_hold` and `p_payload_stable` keyed off a `pipeline_stall` signal declared in the interface but never driven — it sat at `'z`, so both passed vacuously forever. |
| **Clocking blocks** | drivers and monitors sampled with `@(posedge clk); #1ps;` (post-edge). |
| **True back-to-back** | the driver dropped VALID after every item, so `l1_cache_b2b_seq` was not actually back-to-back. |
| **`disable fork` corrupted the sequencer** | the memory driver's reset handling killed the task between `get_next_item` and `item_done`, producing "Get_next_item called twice" and later "item_done() with no outstanding requests". `disable fork` also terminates processes the sequencer spawns; replaced with explicit abort checks at every wait point. |
| **Loop-body declaration initialisers** | `bit [31:0] base = f(i);` inside a `for` body was evaluated **once** by xsim, silently collapsing 24 distinct cache lines into 1 (the passive test reported 191 hits / 1 miss and still "passed"). All such declarations are now split from their assignment. |
| **Helper argument names** | `get_index(a)` / `make_addr(t, i)` used single-letter formals. When a call site had a local with the same name, xsim evaluated the actual argument in the callee's scope and silently passed 0 — this made `l1_cache_eviction_test` generate zero evictions while still passing. |
| **Config object + test hierarchy** | one test with the sequence chosen by commenting lines in and out → `l1_cache_config` plus a base test and eleven scenario tests. |
| **`check_phase` added** | fails on zero traffic, dangling reads, unfulfilled memory predictions, or any mismatch — a silent testbench no longer looks like a pass. |
| **Passive mode is now exercised** | the CPU agent could be built passive but nothing ever ran it, so the monitor was free to grow a hidden dependency on the driver. `l1_cache_passive_test` builds the agent passive and drives the pins from a BFM in the test. |
| **Build scripts** | `files.f`, `run.bat`, `regress.bat` — the build used to be entirely manual. |

---

## 5. Not done yet

**Verification**

* **No register model / RAL.** This is not an oversight to fix with a RAL: the
  DUT has no memory-mapped registers, so there is nothing for a register model
  to abstract. Making RAL meaningful means first adding a CSR block (cache
  enable, software flush, hit/miss performance counters) — a design change, not
  a testbench one. Worth doing; inventing registers purely to demonstrate the
  technique is not.
* **Async reset poisons a small number of lines.** When reset cuts a write-back
  burst in half, DRAM for that line is genuinely unpredictable, so data checks
  for it are skipped for the rest of the run. Bounded (≤1 line per reset) and
  reported. Recovering full checking would mean having the model adopt the
  observed fill data for poisoned lines.
* **Code coverage is not collected.** `xelab -cc` plus `xcrg` would give
  statement/branch/toggle numbers alongside the functional ones.
* **No X-propagation or gate-level run**, and no formal property checking.

**Architecture**

* **Non-blocking misses (MSHR).** The biggest remaining item, and deliberately
  deferred rather than half-done: hit-under-miss means read responses stop
  being in program order, which invalidates the monitor's queue-based response
  matching and the scoreboard's in-order snapshot. It needs response IDs on the
  CPU interface and an ID-matching scoreboard — a testbench redesign as much as
  an RTL one.
* Configurable ways/sets/line size via parameters rather than package
  localparams.
* Critical-word-first fill (return the requested word to the CPU on the beat it
  arrives, instead of waiting for `ST_COMPLETE`).
* A store that covers an entire line could skip the fetch. With 16-byte lines
  and word-sized stores this never happens, so it is only worth doing alongside
  wider stores or per-word dirty bits.
* Write buffer, so a dirty eviction does not serialise in front of the fill.
