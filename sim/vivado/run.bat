@echo off
rem ==========================================================================
rem  L1 cache UVM run - Vivado xsim
rem
rem   run.bat                            :: default test (l1_cache_random_test)
rem   run.bat l1_cache_stress_test       :: pick a test
rem   run.bat l1_cache_stress_test 42    :: pick a test and a seed
rem
rem  Tests: l1_cache_smoke_test        short sanity run, gentle memory
rem         l1_cache_random_test       mixed R/W workhorse           (default)
rem         l1_cache_thrash_test       whole-address-space random, all misses
rem         l1_cache_eviction_test     PLRU / write-back stress, 6 tags per set
rem         l1_cache_b2b_test          true back-to-back, no idle gaps
rem         l1_cache_line_test         multi-word line / spatial locality
rem         l1_cache_be_test           byte enables + per-byte forwarding
rem         l1_cache_stress_test       slow memory + heavy backpressure
rem         l1_cache_passive_test      passive CPU agent, BFM-driven stimulus
rem         l1_cache_reset_test        mid-traffic reset, bus quiesced first
rem         l1_cache_reset_async_test  reset at an arbitrary moment
rem
rem  Artifacts (xsim.dir, *.log, *.jou, *.pb) all land in this directory.
rem ==========================================================================
setlocal

if "%VIVADO_ROOT%"=="" set VIVADO_ROOT=C:\AMDDesignTools\2025.2\Vivado
set PATH=%VIVADO_ROOT%\bin;%PATH%

set TEST=%1
if "%TEST%"=="" set TEST=l1_cache_random_test

set SEED=%2
if "%SEED%"=="" set SEED=1

cd /d "%~dp0"

echo === xvlog =================================================
call xvlog -sv -L uvm -f files.f -log xvlog.log
if errorlevel 1 goto :fail

echo === xelab =================================================
call xelab -L uvm -relax -timescale 1ns/1ps -s l1_cache_tb tb_top -log xelab.log
if errorlevel 1 goto :fail

echo === xsim  (test=%TEST% seed=%SEED%) ========================
call xsim l1_cache_tb -R -sv_seed %SEED% ^
     -testplusarg "UVM_TESTNAME=%TEST%" -log xsim.log
if errorlevel 1 goto :fail

echo.
echo === RESULT ================================================
findstr /C:"SCOREBOARD SUMMARY" /C:"CPU reads" /C:"hits / misses" /C:"Dirty evictions" ^
        /C:"Way utilisation" /C:"Set reach" /C:"Resets / poisoned" ^
        /C:"cache_ops covergroup" /C:"FSM COV" /C:"UVM_ERROR :" /C:"UVM_FATAL :" xsim.log
goto :eof

:fail
echo.
echo *** BUILD/RUN FAILED - see xvlog.log / xelab.log / xsim.log
exit /b 1
