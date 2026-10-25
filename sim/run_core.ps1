# Integration test of flappy_game_core with Verilator ( iverilog is too slow for thousands of frames )
# usage (from the project root):   powershell -ExecutionPolicy Bypass -File sim\run_core.ps1
# needs MSYS2 packages: mingw-w64-ucrt-x86_64-verilator , mingw-w64-ucrt-x86_64-gcc , make
# note: the MSYS2 GCC 16 build fails to link std::string in its default C++20 mode , so we compile with -std=gnu++17
# screenshots are written to sim/out/*.ppm and converted to .png
$root = Split-Path -Parent $PSScriptRoot
$env:PATH    = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;$env:PATH"
$env:MSYSTEM = 'UCRT64'
$unix = ($root -replace '\\','/')
New-Item -ItemType Directory -Force "$root\sim\out" | Out-Null
& C:\msys64\usr\bin\bash.exe -lc "cd '$unix' && rm -rf sim/out/vl_core && verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -j 8 -CFLAGS -std=gnu++17 -CFLAGS -O2 --top-module tb_flappy_game_core --Mdir sim/out/vl_core -o tb_core -I. sim/tb_flappy_game_core.sv sim/course_files.sv RTL/FLAPPY/*.sv > sim/out/vl_core_build.log 2>&1"
if (-not (Test-Path "$root\sim\out\vl_core\tb_core.exe")) { Get-Content "$root\sim\out\vl_core_build.log" | Select-Object -Last 20; Write-Host "BUILD FAILED" -ForegroundColor Red; exit 1 }
Push-Location "$root\sim\out"
$log = & .\vl_core\tb_core.exe
Pop-Location
$log | Write-Host
& powershell -ExecutionPolicy Bypass -File "$root\tools\ppm_to_png.ps1" (Get-ChildItem "$root\sim\out\screen_*.ppm" | ForEach-Object { $_.FullName })
if ($log -match 'ALL TESTS PASSED') { Write-Host "ALL CHECKS OK" -ForegroundColor Green } else { Write-Host "SOME CHECKS FAILED" -ForegroundColor Red; exit 1 }
