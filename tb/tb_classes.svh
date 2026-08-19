// Value main memory returns for a word nobody has written yet.
// Address dependent on purpose: a constant would hide word-select bugs inside
// a line, because every beat of a cold fill would look identical.
// Shared by the memory driver (produces it) and the scoreboard (expects it).
`define L1_MEM_DEFAULT(a) (32'hDEAD_0000 | ((a) & 32'h0000_FFFF))

// 0. Configuration
`include "l1_cache_config.sv"

// 1. Items
`include "agent/l1_cache_item.sv"
`include "agent/l1_cache_mem_item.sv"

// 2. CPU Agent
`include "agent/l1_cache_cpu_sequencer.sv"
`include "agent/l1_cache_cpu_driver.sv"
`include "agent/l1_cache_cpu_monitor.sv"
`include "agent/l1_cache_cpu_agent.sv"

// 3. Memory Agent
`include "agent/l1_cache_mem_sequencer.sv"
`include "agent/l1_cache_mem_driver.sv"
`include "agent/l1_cache_mem_monitor.sv"
`include "agent/l1_cache_mem_agent.sv"

// 4. Reset Agent (item, sequencer, driver, agent and sequence in one file)
`include "agent/l1_cache_reset_agent.sv"

// 5. Coverage, scoreboard, env
`include "env/l1_cache_coverage.sv"
`include "env/l1_cache_scoreboard.sv"
`include "env/l1_cache_env.sv"

// 6. Sequences
`include "seqs/l1_cache_base_seq.sv"
`include "seqs/l1_cache_mem_rsp_seq.sv"
`include "seqs/l1_cache_mix_seq.sv"
`include "seqs/l1_cache_eviction_seq.sv"
`include "seqs/l1_cache_b2b_seq.sv"
`include "seqs/l1_cache_rand_seq.sv"
`include "seqs/l1_cache_line_seq.sv"
`include "seqs/l1_cache_be_seq.sv"

// 7. Tests
`include "tests/l1_cache_base_test.sv"
