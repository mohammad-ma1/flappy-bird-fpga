# Lint (Verilator), simulate (iverilog) and optionally synthesize (Quartus) RTL modules.
# usage (from the project root):   powershell -ExecutionPolicy Bypass -File sim\run_checks.ps1 flappy_objects_mux flappy_game_controller
#        add -Quartus to also run Quartus Analysis & Synthesis on each module
# every module is compiled with all the files of RTL/FLAPPY ( so modules that instantiate others work too )
param([Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)][string[]]$Modules, [switch]$Quartus)

$root   = Split-Path -Parent $PSScriptRoot
$msys   = 'C:\msys64'
$qsh    = 'C:\intelFPGA_lite\17.0\quartus\bin64\quartus_map.exe'
$env:PATH    = "$msys\ucrt64\bin;$msys\usr\bin;$env:PATH"
$env:MSYSTEM = 'UCRT64'
$out = Join-Path $root 'sim\out'
New-Item -ItemType Directory -Force $out | Out-Null
$failed = $false
# the game files + the course files of Lab1Demo that the game uses ( unchanged )
$courseFiles = @("$root\RTL\VGA\square_object.sv")
$rtlFiles  = @(Get-ChildItem "$root\RTL\FLAPPY\*.sv" | ForEach-Object { $_.FullName }) + $courseFiles
$rtlUnix   = ((Get-ChildItem "$root\RTL\FLAPPY\*.sv" | ForEach-Object { 'RTL/FLAPPY/' + $_.Name }) + @('sim/course_files.sv')) -join ' '

foreach ($m in $Modules) {
    Write-Host "===== $m : verilator --lint-only -Wall" -ForegroundColor Cyan
    $unix = ($root -replace '\\','/')
    & "$msys\usr\bin\bash.exe" -lc "cd '$unix' && verilator --lint-only -Wall -Wno-EOFNEWLINE -Wno-ASCRANGE -Wno-UNUSEDSIGNAL -I. --top-module $m $rtlUnix"
    if ($LASTEXITCODE -ne 0) { $failed = $true } else { Write-Host "lint clean" }

    Write-Host "===== $m : iverilog -g2012" -ForegroundColor Cyan
    & iverilog -g2012 -Wall -Wno-timescale -s "tb_$m" -o "$out\$m.vvp" "$root\sim\tb_$m.sv" @rtlFiles
    if ($LASTEXITCODE -ne 0) { $failed = $true; continue }
    Push-Location $out
    $log = & vvp -n "$out\$m.vvp"
    Pop-Location
    $log | Write-Host
    if (-not ($log -match 'ALL TESTS PASSED')) { $failed = $true }

    if ($Quartus -and (Test-Path $qsh)) {
        Write-Host "===== $m : Quartus Analysis & Synthesis" -ForegroundColor Cyan
        # Quartus 17 fails on long paths, so synthesize in a short temp folder
        $qdir = Join-Path $env:TEMP "qchk\$m"
        if (Test-Path $qdir) { Remove-Item $qdir -Recurse -Force }
        New-Item -ItemType Directory -Force $qdir | Out-Null
        $srcArgs = @()
        foreach ($f in $rtlFiles) { Copy-Item $f $qdir -Force; $srcArgs += "--source=$(Split-Path -Leaf $f)" }
        Push-Location $qdir
        & $qsh $m @srcArgs --family="Cyclone V" --part=5CSXFC6D6F31C6 | Select-String -Pattern 'Error|Warning \(|was successful|was unsuccessful'
        if ($LASTEXITCODE -ne 0) { $failed = $true }
        Pop-Location
    }
}
if ($failed) { Write-Host "SOME CHECKS FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL CHECKS OK" -ForegroundColor Green }
