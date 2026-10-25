# Converts the P3 .ppm screenshots written by sim/tb_flappy_game_core.sv to .png
# usage:  powershell -ExecutionPolicy Bypass -File tools\ppm_to_png.ps1 sim\out\screen_start.ppm [more files]
param([Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)][string[]]$Files)
Add-Type -AssemblyName System.Drawing
foreach ($f in $Files) {
    $tok = ([IO.File]::ReadAllText((Resolve-Path $f))) -split '\s+' | Where-Object { $_ -ne '' }
    if ($tok[0] -ne 'P3') { throw "$f is not a P3 ppm" }
    $w = [int]$tok[1]; $h = [int]$tok[2]
    $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    $bytes = New-Object byte[] ($data.Stride * $h)
    $i = 4
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $data.Stride
        for ($x = 0; $x -lt $w; $x++) {
            $o = $row + 3 * $x
            $bytes[$o + 2] = [byte]$tok[$i]; $bytes[$o + 1] = [byte]$tok[$i + 1]; $bytes[$o] = [byte]$tok[$i + 2]   # BGR
            $i += 3
        }
    }
    [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $bmp.UnlockBits($data)
    $png = [IO.Path]::ChangeExtension((Resolve-Path $f).Path, '.png')
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $png"
}
