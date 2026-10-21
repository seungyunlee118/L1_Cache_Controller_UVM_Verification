#!/usr/bin/env python3
"""
Bug-injection (mutation) campaign for the L1 cache testbench.

Each mutant is one deliberate RTL defect: a single exact text substitution in
one RTL file. For every mutant the script copies rtl/, applies the change,
builds it and runs the regression (one seed by default), stopping at the first
failing run.

    KILLED    some run failed - UVM error, SVA failure, timeout or sim error
    SURVIVED  every run passed: the testbench cannot see this bug
    INVALID   the substitution did not apply exactly once, or it did not build
    ERROR     a run failed for a tool reason (license, crash, wall-clock limit),
              so the mutant was not judged; rerun it

An unmutated baseline runs first and must pass, otherwise the campaign stops.

    python3 mutate.py                  # every mutant, 4 at a time
    python3 mutate.py -m C05 P01       # selected mutants
    python3 mutate.py -j 8 -s 1 7      # more parallelism, two seeds
    python3 mutate.py --list           # print the catalogue
    python3 mutate.py --check          # only verify every mutant applies

Writes mutants/report.md and mutants/<id>/ (patched rtl, build and run logs).
"""

import argparse
import concurrent.futures
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.normpath(os.path.join(HERE, "..", "..", "rtl"))
OUT = os.path.join(HERE, "mutants")

CORE = "l1_cache_core.sv"
PKG = "l1_cache_pkg.sv"

# (id, file, original text, mutated text, what the bug is)
# C-mutants live in the controller. P-mutants live in l1_cache_pkg - helpers
# the scoreboard also calls, so they probe for common-mode blindness.
MUTANTS = [
    ("C01", CORE,
     "s2_be    <= cpu_req_be;",
     "s2_be    <= '1;",
     "S2 register drops the byte enables (every store is a full word)"),
    ("C02", CORE,
     "? prev_tag_wdata : tag_rdata[w];",
     "? tag_rdata[w] : tag_rdata[w];",
     "tag read-during-write forwarding removed"),
    ("C03", CORE,
     "(prev_data_waddr == prev_data_raddr) && prev_data_wbe[b])",
     "(prev_data_waddr == prev_data_raddr))",
     "data forwarding ignores byte enables (forwards the whole word)"),
    ("C04", CORE,
     "? prev_data_wdata[b*8 +: 8]",
     "? data_rdata[w][b*8 +: 8]",
     "data read-during-write forwarding removed"),
    ("C05", CORE,
     "(prev_data_we[w] && (prev_data_waddr == prev_data_raddr)",
     "(prev_data_we[w] && (prev_data_waddr == data_raddr)",
     "data forwarding compares this cycle's read address, not last cycle's"),
    ("C06", CORE,
     "way_hit[w] = set_valid[w] && (safe_tag_rdata[w] == s2_tag);",
     "way_hit[w] = (safe_tag_rdata[w] == s2_tag);",
     "hit detection ignores the valid bit"),
    ("C07", CORE,
     "victim_sel = has_invalid ? first_invalid : plru_victim(plru_bits[s2_set]);",
     "victim_sel = plru_victim(plru_bits[s2_set]);",
     "victim choice does not prefer invalid ways"),
    ("C08", CORE,
     "for (int w = WAYS-1; w >= 0; w--) begin",
     "for (int w = 0; w < WAYS; w++) begin",
     "fills the highest invalid way instead of the lowest"),
    ("C09", CORE,
     "assign victim_dirty = set_valid[victim_sel] && set_dirty[victim_sel];",
     "assign victim_dirty = 1'b0;",
     "dirty victims are never written back"),
    ("C10", CORE,
     "assign victim_dirty = set_valid[victim_sel] && set_dirty[victim_sel];",
     "assign victim_dirty = set_valid[victim_sel];",
     "clean victims are written back too"),
    ("C11", CORE,
     "cache_hit && !s2_rw)",
     "cache_hit)",
     "write hits also raise cpu_rsp_valid"),
    ("C12", CORE,
     "assign cpu_rsp_rdata = (state == ST_COMPLETE) ? fill_data : safe_data_rdata[hit_way];",
     "assign cpu_rsp_rdata = safe_data_rdata[hit_way];",
     "miss response returns the array read instead of the captured fill word"),
    ("C13", CORE,
     "plru_bits[s2_set] <= plru_update(plru_bits[s2_set], hit_way);",
     "plru_bits[s2_set] <= plru_bits[s2_set];",
     "PLRU is not updated on hits"),
    ("C14", CORE,
     "if (s2_rw) dirty_bits[s2_set][hit_way] <= 1'b1;",
     "if (s2_rw) dirty_bits[s2_set][hit_way] <= dirty_bits[s2_set][hit_way];",
     "a write hit does not mark the line dirty"),
    ("C15", CORE,
     "if (wb_cnt > 0) wb_buf[wb_cnt-1] <= safe_data_rdata[victim_way];",
     "if (wb_cnt < 4) wb_buf[wb_cnt[1:0]] <= safe_data_rdata[victim_way];",
     "victim buffer captures one cycle early (off by one)"),
    ("C16", CORE,
     "if (fill_beat == s2_word) fill_data <= mem_rd_data;",
     "if (fill_beat == word_t'(0)) fill_data <= mem_rd_data;",
     "a read miss returns fill beat 0 instead of the requested word"),
    ("C17", CORE,
     "dirty_bits[s2_set][victim_way] <= s2_rw;",
     "dirty_bits[s2_set][victim_way] <= 1'b0;",
     "a write miss allocates the line clean"),
    ("C18", CORE,
     "plru_bits [s2_set]             <= plru_update(plru_bits[s2_set], victim_way);",
     "plru_bits [s2_set]             <= plru_bits[s2_set];",
     "PLRU is not updated on fills"),
    ("C19", CORE,
     "valid_bits[s] <= '0;",
     "valid_bits[s] <= valid_bits[s];",
     "reset does not invalidate the cache"),
    ("C20", CORE,
     "pipeline_stall = 1'b1;\n                        next_state     = victim_dirty",
     "pipeline_stall = 1'b0;\n                        next_state     = victim_dirty",
     "S1 is not stalled in the cycle a miss is detected"),
    ("C21", CORE,
     "if (wb_cnt == 3'd4) next_state = ST_WB_SEND;",
     "if (wb_cnt == 3'd3) next_state = ST_WB_SEND;",
     "write-back starts before the last victim word is buffered"),
    ("C22", CORE,
     "mem_req_addr  = make_line_addr(victim_tag, s2_set);",
     "mem_req_addr  = make_line_addr(s2_tag, s2_set);",
     "write-back is sent to the new line's address"),
    ("C23", CORE,
     "mem_wr_last  = (wb_ptr == word_t'(WORDS_PER_LINE-1));",
     "mem_wr_last  = (wb_ptr == word_t'(WORDS_PER_LINE-2));",
     "write-back LAST raised one beat early"),
    ("C24", CORE,
     "mem_req_len    = WORDS_PER_LINE - 1;",
     "mem_req_len    = WORDS_PER_LINE;",
     "burst length field off by one"),
    ("C25", CORE,
     "data_waddr          = make_data_addr(s2_set, fill_beat);",
     "data_waddr          = make_data_addr(s2_set, s2_word);",
     "every fill beat lands in the requested word"),
    ("C26", CORE,
     "data_we[victim_way] = 1'b1;\n                    data_wbe            = s2_be;",
     "data_we[victim_way] = 1'b1;\n                    data_wbe            = '1;",
     "a write miss merges the store with all byte enables"),
    ("C27", CORE,
     "tag_we[victim_way] = 1'b1;\n                if (s2_rw) begin",
     "tag_we[victim_way] = 1'b1;\n                if (1'b0) begin",
     "a write miss drops the store after the fill"),
    ("C28", CORE,
     "data_we[hit_way] = 1'b1;",
     "data_we[victim_sel] = 1'b1;",
     "a write hit updates the victim way instead of the hit way"),

    ("P01", PKG,
     "nxt[0] = ~way_in[1];",
     "nxt[0] = way_in[1];",
     "PLRU root points at the touched half instead of away from it"),
    ("P02", PKG,
     "return plru_in[0] ? (plru_in[2] ? way_t'(3) : way_t'(2))",
     "return plru_in[0] ? (plru_in[2] ? way_t'(2) : way_t'(3))",
     "PLRU victim decode swaps ways 2 and 3"),
    ("P03", PKG,
     "return addr_in[OFFSET_BITS +: SET_BITS];",
     "return addr_in[OFFSET_BITS+1 +: SET_BITS];",
     "set index taken one bit too high (overlaps the tag)"),
    ("P04", PKG,
     "return addr_in[BYTE_BITS +: WORD_BITS];",
     "return addr_in[BYTE_BITS+1 +: WORD_BITS];",
     "word select taken one bit too high (overlaps the set index)"),
]


# Mutants that no pin-level testbench can kill, with the reason. They are run
# anyway - one that dies proves the reasoning wrong - but a survivor is
# reported EQUIVALENT and left out of the score.
EQUIVALENT = {
    "C08": "Tree-PLRU is symmetric under the relabelling way w <-> 3-w (swap the "
           "pairs and the ways inside them). Filling invalid ways highest-first "
           "is that relabelling of lowest-first, and the PLRU state is fully "
           "rewritten before any victim decision reads it, so every hit, miss, "
           "victim line and write-back is identical. Way numbers never reach "
           "the pins.",
}


# Simulator message codes that are testbench checks rather than tool trouble.
# EILLTB is an illegal_bins hit in the FSM covergroup.
SIM_CHECKS = {"EILLTB"}


def is_testbench_check(reason):
    """True if a failing run was stopped by the testbench (a UVM report, an
    SVA, an illegal bin, the UVM timeout), False for infrastructure trouble -
    a license, a crash, the wall-clock limit - which says nothing about
    whether the bug was caught."""
    if reason.startswith("SIM:"):
        return reason[4:] in SIM_CHECKS
    return reason not in ("WALL_TIMEOUT", "NO_REPORT", "NO_SUMMARY")


def prepare(mid, fname, old, new):
    """Copy rtl/ into mutants/<mid>/rtl, apply the change, write a filelist.
    Returns an error string, or None."""
    work = os.path.join(OUT, mid)
    if os.path.isdir(work):
        shutil.rmtree(work)
    shutil.copytree(RTL, os.path.join(work, "rtl"))

    if fname is not None:
        path = os.path.join(work, "rtl", fname)
        with open(path) as f:
            text = f.read()
        n = text.count(old)
        if n != 1:
            return "original text found %d times in %s" % (n, fname)
        with open(path, "w") as f:
            f.write(text.replace(old, new))

    # Absolute paths: regress.sh builds from inside the mutant's own directory.
    root = os.path.normpath(os.path.join(HERE, "..", ".."))
    with open(os.path.join(HERE, "files.f")) as f:
        flist = (f.read().replace("../../rtl/", os.path.join(work, "rtl") + "/")
                          .replace("../../", root + "/"))
    with open(os.path.join(work, "files.f"), "w") as f:
        f.write(flist)
    return None


def run(mid, seeds):
    """Build and regress one prepared mutant. Returns (status, detail, secs)."""
    work = os.path.join(OUT, mid)
    t0 = time.time()
    subprocess.run(
        ["./regress.sh", "-q", "-k", "-j", "1", "-s", " ".join(seeds),
         "-f", os.path.relpath(os.path.join(work, "files.f"), HERE),
         "-o", os.path.relpath(work, HERE)],
        cwd=HERE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    secs = int(time.time() - t0)

    res = os.path.join(work, "results.txt")
    if not os.path.exists(res):
        return "INVALID", "no results", secs
    lines = [l.split() for l in open(res) if l.strip()]
    if lines and lines[0][0] == "BUILD_FAILED":
        return "INVALID", "does not build", secs
    for f in lines:
        if f[2] == "FAIL":
            detail = "%s seed %s: %s" % (f[0].replace("l1_cache_", ""), f[1], f[3])
            if not is_testbench_check(f[3]):
                return "ERROR", detail, secs
            return "KILLED", detail, secs
    if mid in EQUIVALENT:
        return "EQUIVALENT", "%d run(s) passed (see note)" % len(lines), secs
    return "SURVIVED", "%d run(s) passed" % len(lines), secs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-m", nargs="+", metavar="ID", help="mutant ids to run")
    ap.add_argument("-s", nargs="+", default=["1"], metavar="SEED", help="seeds (default 1)")
    ap.add_argument("-j", type=int, default=4, help="mutants run in parallel (default 4)")
    ap.add_argument("--list", action="store_true", help="print the catalogue and exit")
    ap.add_argument("--check", action="store_true", help="only verify each mutant applies")
    args = ap.parse_args()

    todo = [m for m in MUTANTS if not args.m or m[0] in args.m]
    if args.list:
        for mid, fname, _, _, desc in todo:
            print("%s  %-16s %s" % (mid, fname, desc))
        return 0

    os.makedirs(OUT, exist_ok=True)
    bad = [(m[0], prepare(*m[:4])) for m in todo]
    bad = [(mid, err) for mid, err in bad if err]
    for mid, err in bad:
        print("%s: %s" % (mid, err))
    if args.check or bad:
        return 1 if bad else 0

    print("baseline (no mutation) ...", flush=True)
    prepare("base", None, None, None)
    status, detail, _ = run("base", args.s)
    if status != "SURVIVED":
        print("baseline does not pass (%s) - fix the testbench first" % detail)
        return 1

    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.j) as pool:
        futs = {pool.submit(run, m[0], args.s): m for m in todo}
        for fut in concurrent.futures.as_completed(futs):
            m = futs[fut]
            results[m[0]] = fut.result()
            st, detail, secs = results[m[0]]
            print("  %-3s %-8s %-60s %s" % (m[0], st, m[4][:60], detail), flush=True)

    killed = sum(1 for r in results.values() if r[0] == "KILLED")
    valid = sum(1 for r in results.values() if r[0] in ("KILLED", "SURVIVED"))
    equiv = [mid for mid, r in sorted(results.items()) if r[0] == "EQUIVALENT"]
    errors = [mid for mid, r in sorted(results.items()) if r[0] == "ERROR"]
    score = 100.0 * killed / valid if valid else 0.0

    with open(os.path.join(OUT, "report.md"), "w") as f:
        f.write("# Mutation campaign\n\n")
        f.write("Seeds: %s. Killed %d / %d non-equivalent mutants (%.1f%%), "
                "%d equivalent.\n\n" % (" ".join(args.s), killed, valid, score, len(equiv)))
        f.write("| ID | File | Injected bug | Result | First failing run |\n")
        f.write("|---|---|---|---|---|\n")
        for mid, fname, _, _, desc in todo:
            st, detail, _ = results[mid]
            f.write("| %s | %s | %s | %s | %s |\n" % (mid, fname, desc, st, detail))
        for mid in equiv:
            f.write("\n**%s is equivalent.** %s\n" % (mid, EQUIVALENT[mid]))
        if errors:
            f.write("\n**Not judged (tool error, rerun):** %s\n" % ", ".join(errors))

    print("\nkilled %d / %d non-equivalent mutants (%.1f%%), %d equivalent - report: mutants/report.md"
          % (killed, valid, score, len(equiv)))
    if errors:
        print("%d mutant(s) hit a tool error and were not judged: %s" % (len(errors), " ".join(errors)))
        return 4
    return 0 if killed == valid else 3


if __name__ == "__main__":
    sys.exit(main())
