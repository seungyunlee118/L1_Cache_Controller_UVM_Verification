@echo off
rem ==========================================================================
rem  Regression: every test x a set of seeds, then a MERGED coverage report.
rem
rem  Compiles once, re-runs the elaborated snapshot per (test, seed), saves a
rem  separate functional-coverage database per run, and merges them all with
rem  xcrg at the end.  Per-run logs: regr_<test>_<seed>.log
rem  Merged report: xsim_coverage_report/functionalCoverageReport/
rem ==========================================================================
setlocal enabledelayedexpansion

if "%VIVADO_ROOT%"=="" set VIVADO_ROOT=C:\AMDDesignTools\2025.2\Vivado
set PATH=%VIVADO_ROOT%\bin;%PATH%

cd /d "%~dp0"

rem Stale databases would silently inflate the merged score.
if exist xsim.covdb rmdir /s /q xsim.covdb
if exist xsim_coverage_report rmdir /s /q xsim_coverage_report

call xvlog -sv -L uvm -f files.f -log xvlog.log
if errorlevel 1 exit /b 1
call xelab -L uvm -relax -timescale 1ns/1ps -s l1_cache_tb tb_top -log xelab.log
if errorlevel 1 exit /b 1

set FAILED=0
echo.
echo ==================== REGRESSION ====================

for %%T in (l1_cache_smoke_test l1_cache_random_test l1_cache_thrash_test
            l1_cache_eviction_test l1_cache_b2b_test l1_cache_line_test
            l1_cache_be_test l1_cache_stress_test l1_cache_passive_test
            l1_cache_reset_test l1_cache_reset_async_test) do (
  for %%D in (1 7 42 999) do (
    call xsim l1_cache_tb -R -sv_seed %%D ^
         -testplusarg "UVM_TESTNAME=%%T" ^
         -cov_db_name %%T_%%D -log regr_%%T_%%D.log > nul 2>&1

    findstr /C:"UVM_ERROR :    0" regr_%%T_%%D.log > nul
    if errorlevel 1 (
      echo   FAIL  %%T  seed=%%D
      set /a FAILED+=1
    ) else (
      findstr /C:"UVM_FATAL :    0" regr_%%T_%%D.log > nul
      if errorlevel 1 (
        echo   FAIL  %%T  seed=%%D  ^(fatal^)
        set /a FAILED+=1
      ) else (
        for /f "tokens=2 delims==" %%C in ('findstr /C:"FUNCCOV=" regr_%%T_%%D.log') do (
          echo   pass  %%T  seed=%%D  funccov=%%C%%
        )
      )
    )
  )
)

echo ====================================================
if not %FAILED%==0 (echo REGRESSION FAILED: %FAILED% run^(s^) & exit /b 1)

echo REGRESSION PASSED
echo.
echo ==================== MERGED COVERAGE ================
call xcrg -merge_db_name merged -report_format text -log xcrg.log > nul 2>&1
for /f "tokens=2 delims=:," %%S in ('findstr /C:"Coverage Score" xsim_coverage_report\functionalCoverageReport\xcrg_func_cov_report.txt') do (
  echo   merged functional coverage : %%S%%
)
echo   report: xsim_coverage_report\functionalCoverageReport\xcrg_func_cov_report.txt
echo ====================================================
