# SimVision view for waves.shm (make WAVE=1, then make view).
# Opens one waveform window with the CPU port, the controller pipeline/FSM
# and the three memory channels, each under a divider. Add more signals from
# the Design Browser, then File > Save Command Script to keep your own layout.

window new WaveWindow -name "L1 cache"
waveform using "L1 cache"

waveform add -cdivider "Clock / reset"
waveform add -signals {
    waves::tb_top.clk
    waves::tb_top.vif.rst_n
}

waveform add -cdivider "CPU request / response"
waveform add -signals {
    waves::tb_top.vif.cpu_req_valid
    waves::tb_top.vif.cpu_req_ready
    waves::tb_top.vif.cpu_req_rw
    waves::tb_top.vif.cpu_req_addr
    waves::tb_top.vif.cpu_req_be
    waves::tb_top.vif.cpu_req_wdata
    waves::tb_top.vif.cpu_rsp_valid
    waves::tb_top.vif.cpu_rsp_rdata
}

waveform add -cdivider "Controller: S2 stage and miss FSM"
waveform add -signals {
    waves::tb_top.u_dut.u_core.s2_valid
    waves::tb_top.u_dut.u_core.s2_addr
    waves::tb_top.u_dut.u_core.cache_hit
    waves::tb_top.u_dut.u_core.hit_way
    waves::tb_top.u_dut.u_core.pipeline_stall
    waves::tb_top.u_dut.u_core.state
    waves::tb_top.u_dut.u_core.victim_way
    waves::tb_top.u_dut.u_core.fill_beat
}

waveform add -cdivider "Memory request"
waveform add -signals {
    waves::tb_top.vif.mem_req_valid
    waves::tb_top.vif.mem_req_ready
    waves::tb_top.vif.mem_req_rw
    waves::tb_top.vif.mem_req_addr
    waves::tb_top.vif.mem_req_len
}

waveform add -cdivider "Write-back data (cache -> memory)"
waveform add -signals {
    waves::tb_top.vif.mem_wr_valid
    waves::tb_top.vif.mem_wr_ready
    waves::tb_top.vif.mem_wr_data
    waves::tb_top.vif.mem_wr_last
}

waveform add -cdivider "Fill data (memory -> cache)"
waveform add -signals {
    waves::tb_top.vif.mem_rd_valid
    waves::tb_top.vif.mem_rd_data
    waves::tb_top.vif.mem_rd_last
}

# Start on the first misses after reset; zoom out from here.
waveform xview limits 0ns 1500ns
