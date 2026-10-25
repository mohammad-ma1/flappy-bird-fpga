# Generates the font and text-line tables of RTL/FLAPPY/flappy_text_draw.sv
# usage:  powershell -ExecutionPolicy Bypass -File tools\gen_text_tables.ps1
# It rewrites the part of flappy_text_draw.sv between the "// ---- generated tables" markers.
#
# Text codes : 0-9 digits , 10-35 A-Z , 36 space , 37 '!'
#   ^ = score digit (the k-th ^ in a line is digit k , thousands first)  -> codes 48..51
#   ~ = best score digit                                                 -> codes 52..55
#   @ = level digit                                                      -> code  56

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'RTL\FLAPPY\flappy_text_draw.sv'

# ---------------- the text lines : 4 lines per game state (0 START , 1 PLAY , 2 GAME_OVER , 3 unused)
# shift 1 = font x2 (16 px cells) , shift 2 = font x4 (32 px cells) . colors RGB 3-3-2
# fx : 0 steady , 1 blinking ( on / off every half second ) , 2 rainbow ( cycles through bright colors )
$lines = @(
  @{ t='READY!';                 y=96;  x=224; s=2; c='FC'; fx=2 },   # 0 START ( rainbow )
  @{ t='PRESS ENTER TO START';   y=232; x=160; s=1; c='FE'; fx=1 },   #   blinking
  @{ t='8 UP   2 DOWN';          y=272; x=216; s=1; c='1F'; fx=0 },
  @{ t='BEST ~~~~';              y=312; x=248; s=1; c='FC'; fx=0 },
  @{ t='SCORE ^^^^';             y=12;  x=12;  s=1; c='FE'; fx=0 },   # 4 PLAY ( HUD )
  @{ t='LEVEL @';                y=12;  x=516; s=1; c='FE'; fx=0 },
  @{ t='';                       y=0;   x=0;   s=1; c='00'; fx=0 },   # 6 not used
  @{ t='REVERSED';               y=12;  x=256; s=1; c='E0'; fx=0 },   # 7 shown only while the controls are inverted
  @{ t='GAME OVER';              y=96;  x=176; s=2; c='E0'; fx=0 },   # 8 GAME_OVER ( bright red )
  @{ t='SCORE ^^^^';             y=216; x=240; s=1; c='FE'; fx=0 },
  @{ t='BEST ~~~~';              y=256; x=248; s=1; c='FC'; fx=0 },
  @{ t='PRESS ENTER TO RESTART'; y=312; x=144; s=1; c='FE'; fx=1 },   #   blinking
  @{ t='';                       y=0;   x=0;   s=1; c='00'; fx=0 },   # 12 state 3 - not used
  @{ t='';                       y=0;   x=0;   s=1; c='00'; fx=0 },
  @{ t='';                       y=0;   x=0;   s=1; c='00'; fx=0 },
  @{ t='';                       y=0;   x=0;   s=1; c='00'; fx=0 }
)

# ---------------- event messages ( PLAY ) : msgId from flappy_game_controller , a title ( x4 ) and a line under it ( x2 ) ,
# centered on the screen . table entry = msgId * 2 + ( 0 title , 1 subtitle ) . colors RGB 3-3-2
$messages = @(
  @{ t='';                s='';             tc='00'; sc='00' },   # 0 none
  @{ t='GO!';             s='8 UP  2 DOWN';  tc='1C'; sc='FE' },   # 1 a new game
  @{ t='LEVEL @!';        s='FASTER PIPES';  tc='FC'; sc='FE' },   # 2 level up ( the pipes get faster )
  @{ t='INVISIBLE MAZE!'; s='LEVEL @';       tc='9F'; sc='FE' },   # 3 level up to the invisible maze
  @{ t='CLOSING PIPES!';  s='LEVEL @';       tc='E0'; sc='FE' },   # 4 level up to the crushing pipes
  @{ t='LEVEL @!';        s='KEEP GOING!';   tc='FC'; sc='FE' },   # 5 level up ( top speed )
  @{ t='NIGHT MODE!';     s='5 SECONDS';     tc='FE'; sc='FC' },   # 6
  @{ t='SHIELD!';         s='10 SECONDS';    tc='1F'; sc='FE' },   # 7
  @{ t='SLOW MOTION!';    s='10 SECONDS';    tc='F4'; sc='FE' },   # 8
  @{ t='REVERSED KEYS!';  s='7 SECONDS';     tc='E3'; sc='FE' },   # 9
  @{ t='PIPE BROKEN!';    s='SHIELD USED';   tc='1F'; sc='FE' }    # 10
)
$MSG_ENTRIES = 32     # 16 messages x 2 lines

# ---------------- 5x7 font
$font = [ordered]@{
 '0'=@('.###.','#...#','#..##','#.#.#','##..#','#...#','.###.')
 '1'=@('..#..','.##..','..#..','..#..','..#..','..#..','.###.')
 '2'=@('.###.','#...#','....#','...#.','..#..','.#...','#####')
 '3'=@('#####','...#.','..#..','...#.','....#','#...#','.###.')
 '4'=@('...#.','..##.','.#.#.','#..#.','#####','...#.','...#.')
 '5'=@('#####','#....','####.','....#','....#','#...#','.###.')
 '6'=@('..##.','.#...','#....','####.','#...#','#...#','.###.')
 '7'=@('#####','....#','...#.','..#..','.#...','.#...','.#...')
 '8'=@('.###.','#...#','#...#','.###.','#...#','#...#','.###.')
 '9'=@('.###.','#...#','#...#','.####','....#','...#.','.##..')
 'A'=@('.###.','#...#','#...#','#####','#...#','#...#','#...#')
 'B'=@('####.','#...#','#...#','####.','#...#','#...#','####.')
 'C'=@('.###.','#...#','#....','#....','#....','#...#','.###.')
 'D'=@('###..','#..#.','#...#','#...#','#...#','#..#.','###..')
 'E'=@('#####','#....','#....','####.','#....','#....','#####')
 'F'=@('#####','#....','#....','####.','#....','#....','#....')
 'G'=@('.###.','#...#','#....','#.###','#...#','#...#','.####')
 'H'=@('#...#','#...#','#...#','#####','#...#','#...#','#...#')
 'I'=@('.###.','..#..','..#..','..#..','..#..','..#..','.###.')
 'J'=@('..###','...#.','...#.','...#.','...#.','#..#.','.##..')
 'K'=@('#...#','#..#.','#.#..','##...','#.#..','#..#.','#...#')
 'L'=@('#....','#....','#....','#....','#....','#....','#####')
 'M'=@('#...#','##.##','#.#.#','#.#.#','#...#','#...#','#...#')
 'N'=@('#...#','#...#','##..#','#.#.#','#..##','#...#','#...#')
 'O'=@('.###.','#...#','#...#','#...#','#...#','#...#','.###.')
 'P'=@('####.','#...#','#...#','####.','#....','#....','#....')
 'Q'=@('.###.','#...#','#...#','#...#','#.#.#','#..#.','.##.#')
 'R'=@('####.','#...#','#...#','####.','#.#..','#..#.','#...#')
 'S'=@('.####','#....','#....','.###.','....#','....#','####.')
 'T'=@('#####','..#..','..#..','..#..','..#..','..#..','..#..')
 'U'=@('#...#','#...#','#...#','#...#','#...#','#...#','.###.')
 'V'=@('#...#','#...#','#...#','#...#','#...#','.#.#.','..#..')
 'W'=@('#...#','#...#','#...#','#.#.#','#.#.#','#.#.#','.#.#.')
 'X'=@('#...#','#...#','.#.#.','..#..','.#.#.','#...#','#...#')
 'Y'=@('#...#','#...#','.#.#.','..#..','..#..','..#..','..#..')
 'Z'=@('#####','....#','...#.','..#..','.#...','#....','#####')
 ' '=@('.....','.....','.....','.....','.....','.....','.....')
 '!'=@('..#..','..#..','..#..','..#..','..#..','.....','..#..')
}

function CharCode([char]$ch, [ref]$cnt) {
  if ($ch -ge '0' -and $ch -le '9') { return [int]$ch - [int][char]'0' }
  if ($ch -ge 'A' -and $ch -le 'Z') { return 10 + [int]$ch - [int][char]'A' }
  if ($ch -eq ' ') { return 36 }
  if ($ch -eq '!') { return 37 }
  if ($ch -eq '^') { $k = $cnt.Value['^']; $cnt.Value['^'] = $k + 1; return 48 + $k }
  if ($ch -eq '~') { $k = $cnt.Value['~']; $cnt.Value['~'] = $k + 1; return 52 + $k }
  if ($ch -eq '@') { return 56 }
  throw "character '$ch' is not in the font"
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add('// ---- generated tables ( tools\gen_text_tables.ps1 ) - do not edit by hand ----')
$out.Add('// 5x7 font : 38 characters ( 0-9 , A-Z , space , ! ) , 7 rows of 5 pixels , bit 4 = left pixel')
$out.Add('logic [0:37][0:6][4:0] FONT = {')
$keys = @($font.Keys)
for ($g = 0; $g -lt $keys.Count; $g++) {
  $rows = $font[$keys[$g]]
  if ($rows.Count -ne 7) { throw "glyph $($keys[$g]) rows" }
  $bits = ($rows | ForEach-Object { if ($_.Length -ne 5) { throw "glyph $($keys[$g]) width" }; "5'b" + $_.Replace('.','0').Replace('#','1') }) -join ', '
  $sep = if ($g -lt $keys.Count - 1) { ',' } else { '' }
  $out.Add("`t$bits$sep   // '$($keys[$g])'")
}
$out.Add('};')
$out.Add('')
$out.Add('// text lines : line = { gameState , 0..3 }')
$ys=@(); $xs=@(); $ss=@(); $ls=@(); $cs=@(); $fs=@(); $txt=@()
for ($i = 0; $i -lt 16; $i++) {
  $L = $lines[$i]
  if ($L.t.Length -gt 31) { throw "line $i too long" }
  $cnt = @{ '^'=0; '~'=0; '#'=0 }
  $codes = @()
  foreach ($ch in $L.t.ToCharArray()) { $codes += (CharCode $ch ([ref]$cnt)) }
  while ($codes.Count -lt 32) { $codes += 36 }
  $ys += "9'd$($L.y)"; $xs += "10'd$($L.x)"; $ss += "2'd$($L.s)"; $ls += "5'd$($L.t.Length)"; $cs += "8'h$($L.c)"; $fs += "2'd$($L.fx)"
  $sep = if ($i -lt 15) { ',' } else { '' }
  $txt += "`t{" + (($codes | ForEach-Object { "6'd$_" }) -join ',') + "}$sep   // $i `"$($L.t)`""
}
$out.Add('logic [0:15][8:0] LINE_Y     = {' + ($ys -join ',') + '};')
$out.Add('logic [0:15][9:0] LINE_X     = {' + ($xs -join ',') + '};')
$out.Add('logic [0:15][1:0] LINE_SHIFT = {' + ($ss -join ',') + '};   // 1 : font x2 , 2 : font x4')
$out.Add('logic [0:15][4:0] LINE_LEN   = {' + ($ls -join ',') + '};   // characters')
$out.Add('logic [0:15][7:0] LINE_COLOR = {' + ($cs -join ',') + '};')
$out.Add('logic [0:15][1:0] LINE_FX    = {' + ($fs -join ',') + '};   // 0 steady , 1 blinking , 2 rainbow')
# ---- the message tables
$mx=@(); $ml=@(); $mc=@(); $mt=@()
for ($e = 0; $e -lt $MSG_ENTRIES; $e++) {
  $m = if ([int][math]::Floor($e / 2) -lt $messages.Count) { $messages[[int][math]::Floor($e / 2)] } else { @{ t=''; s=''; tc='00'; sc='00' } }
  $isSub = ($e % 2) -eq 1
  $txtE = if ($isSub) { $m.s } else { $m.t }
  $colE = if ($isSub) { $m.sc } else { $m.tc }
  $scale = if ($isSub) { 2 } else { 4 }
  if ($txtE.Length -gt 20) { throw "message $e too long" }
  if (-not $isSub -and $txtE.Length -gt 15) { throw "title $e too long" }
  $width = [math]::Max(0, $txtE.Length * 8 * $scale - 3 * $scale)     # the last cell has 3 empty font columns
  $x = [int](320 - $width / 2)
  $cnt = @{ '^'=0; '~'=0; '#'=0 }
  $codes = @(); foreach ($ch in $txtE.ToCharArray()) { $codes += (CharCode $ch ([ref]$cnt)) }
  while ($codes.Count -lt 20) { $codes += 36 }
  $mx += "10'd$x"; $ml += "5'd$($txtE.Length)"; $mc += "8'h$colE"
  $sep = if ($e -lt $MSG_ENTRIES - 1) { ',' } else { '' }
  $mt += "`t{" + (($codes | ForEach-Object { "6'd$_" }) -join ',') + "}$sep   // $e ""$txtE"""
}
$out.Add('// event messages : entry = msgId * 2 + ( 0 title x4 at MSG_TITLE_Y , 1 subtitle x2 at MSG_SUB_Y )')
$out.Add('logic [0:31][9:0] MSG_X     = {' + ($mx -join ',') + '};')
$out.Add('logic [0:31][4:0] MSG_LEN   = {' + ($ml -join ',') + '};')
$out.Add('logic [0:31][7:0] MSG_COLOR = {' + ($mc -join ',') + '};')
$out.Add('logic [0:31][0:19][5:0] MSG_TEXT = {')
$mt | ForEach-Object { $out.Add($_) }
$out.Add('};')
$out.Add('logic [0:15][0:31][5:0] LINE_TEXT = {')
$txt | ForEach-Object { $out.Add($_) }
$out.Add('};')
$out.Add('// ---- end of generated tables ----')

$src = [IO.File]::ReadAllText($target)
$start = $src.IndexOf('// ---- generated tables')
$endMark = '// ---- end of generated tables ----'
$end = $src.IndexOf($endMark)
if ($start -lt 0 -or $end -lt 0) { throw 'markers not found in flappy_text_draw.sv' }
$new = $src.Substring(0, $start) + ($out -join "`n") + $src.Substring($end + $endMark.Length)
[IO.File]::WriteAllText($target, $new, (New-Object Text.UTF8Encoding $false))
Write-Host "tables written to $target"
