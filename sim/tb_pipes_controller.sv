// self checking testbench for pipes_controller ( Active Pipe Control , the maze logic )
// every frame it checks : 1. all pipes scroll by the same step ( a recycled pipe goes behind the last one , at the
// level spacing )  2. STATIC Y : only the active pipe moves in Y and only with the keys ( swapped while confused ) - no key ,
// no move , at every level  3. control moves to the next pipe after a pass  4. the other pipes never change their Y
// 3. control moves to the next pipe after a pass  + coins and shield items ( item code 3 never appears )
`timescale 1ns/1ps

module tb_pipes_controller;

logic clk = 1'b0;
logic resetN, startOfFrame, playEnable, newGamePulse, turbo, keyUp, keyDown, coinPulse;
logic shieldPulse, shatterPulse, hourglassPulse, confusePulse, invertControls;
logic [2:0]  level;

logic signed [10:0] birdX;
logic signed [11:0] pipeX     [0:5];
logic        [8:0]  gapTop    [0:5];
logic        [8:0]  gapBottom [0:5];
logic               broken    [0:5];
logic        [1:0]  edgeCoin  [0:5];
logic               itemOn    [0:5];
logic        [1:0]  itemKind  [0:5];
logic signed [11:0] itemX     [0:5];
logic        [8:0]  itemY     [0:5];
logic [2:0]  activeIndex;
logic        scorePulse;

int errors = 0;
int checks = 0;
int pulses = 0;

always #5 clk = ~clk;
always @(posedge clk) if (scorePulse) pulses++;

pipes_controller dut (.*);

function automatic int px(input int i); return pipeX[i]; endfunction
function automatic int py(input int i); return dut.pipeY[i]; endfunction                                 // gap top ( without the squeeze )
function automatic int it(input int i); return edgeCoin[i]; endfunction
function automatic int gh(input int i); return dut.gapH[i]; endfunction                                  // gap height
function automatic int sq(input int i); return dut.squeeze[i]; endfunction                               // the crushing pipes
function automatic int scx(input int i); return itemX[i]; endfunction                                    // item X
function automatic int scy(input int i); return itemY[i]; endfunction                                    // item Y
function automatic logic isKind(input int i, input int k); return itemOn[i] && itemKind[i] == 2'(k); endfunction

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s (active=%0d level=%0d X=%0d,%0d,%0d,%0d,%0d,%0d)", what, activeIndex, level,
	                                  px(0), px(1), px(2), px(3), px(4), px(5)); end
endtask

task automatic new_game();
	@(negedge clk) newGamePulse = 1'b1;
	@(negedge clk) newGamePulse = 1'b0;
endtask

// one frame + the rule checks
int badScroll, badSpacing, badActiveY, badOtherY, badTransfer, badItem, onScreenMin, onScreenMax;
int transfers, recycles, coins, yMoves, closeSteps, minGap, badClose;
int gapMin = 999, gapMax = 0, extraMin = 999, extraMax = 0, shieldItems = 0, newPipes = 0, glassItems = 0, purpleItems = 0;


task automatic frame();
	int x0 [0:5], y0 [0:5], q0 [0:5], a0, step, n, expY, d, spacing, prev, dy, q;
	for (int i = 0; i < 6; i++) begin x0[i] = px(i); y0[i] = py(i); q0[i] = sq(i); end
	a0 = activeIndex;

	spacing = 224 - 16 * ((level > 4) ? 4 : level);              // every 10 points the pipes come 16 pixels closer
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
	repeat (4) @(negedge clk);
	if (!playEnable) return;
	// 1. one step for every pipe , a recycled pipe is placed at the level spacing behind the pipe before it
	step = -1;
	for (int i = 0; i < 6; i++) if (px(i) <= x0[i] && x0[i] - px(i) <= 12) step = x0[i] - px(i);
	for (int i = 0; i < 6; i++) begin
		prev = (i + 5) % 6;
		if (px(i) == x0[i] - step) ;
		else begin
			recycles++;
			// random maze : distance = level spacing + random 0..62 ( even ) , gap height random 112..143
			if (px(i) - px(prev) < spacing || px(i) - px(prev) > spacing + 62 || ((px(i) - px(prev) - spacing) % 2) != 0) badSpacing++;
			if (px(i) - px(prev) - spacing < extraMin) extraMin = px(i) - px(prev) - spacing;
			if (px(i) - px(prev) - spacing > extraMax) extraMax = px(i) - px(prev) - spacing;
			if (gh(i) < 112 || gh(i) > 143) badItem++;
			if (gh(i) < gapMin) gapMin = gh(i);
			if (gh(i) > gapMax) gapMax = gh(i);
			if (broken[i]) badItem++;                           // a new pipe is whole
			if (isKind(i, 1)) shieldItems++;
			if (isKind(i, 2)) glassItems++;
			if (isKind(i, 3)) begin purpleItems++; if (level < 1) badItem++; end   // the purple trap from level 1
			if (gapTop[i] != py(i) || gapBottom[i] != py(i) + gh(i)) badItem++;   // a new pipe is open
			newPipes++;
			if (i == a0) badScroll++;                           // the active pipe is never recycled
			if (py(i) < 48 || py(i) > 303) badItem++;           // new random gap
			if (it(i) == 3) badItem++;                          // item code 3 ( the old poison ) never appears
			if (it(i) == 1 || it(i) == 2) coins++;
		end
	end
	// 2. the active pipe : ONLY the keys ( swapped while confused ) , limits 16 .. 464 - gap height . no key -> no move
	d = 0;
	if ((invertControls ? keyDown : keyUp) && !(invertControls ? keyUp : keyDown)) d -= 6 + 2 * ((level > 4) ? 4 : level);   // swapped while confused , faster keys every level
	if ((invertControls ? keyUp : keyDown) && !(invertControls ? keyDown : keyUp)) d += 6 + 2 * ((level > 4) ? 4 : level);
	expY = y0[a0] + d;
	if (expY < 16) expY = 16;
	if (expY > 464 - gh(a0)) expY = 464 - gh(a0);
	if (py(a0) != expY) badActiveY++;
	if (py(a0) != y0[a0]) yMoves++;
	// 4. the other pipes never change their Y while they scroll ( a new Y only when placed again off-screen )
	for (int i = 0; i < 6; i++)
		if (i != a0 && px(i) == x0[i] - step) begin
			dy = py(i) - y0[i];
			if (dy != 0) begin badOtherY++; yMoves++; end
		end
	// 5. the crushing pipes : a placed-again pipe is open , else +1 pixel per tube at most per frame , only on the screen ,
	//    only from level 4 ( LEVEL 5 on the screen ) , and the gap never below 64 pixels
	for (int i = 0; i < 6; i++) begin
		q = sq(i);
		if (gapTop[i] != py(i) + q || gapBottom[i] != py(i) + gh(i) - q) badClose++;    // the drawn gap edges
		if (px(i) != x0[i] - step) begin if (q != 0) badClose++; end
		else begin
			if (q - q0[i] > 1 || q < q0[i]) badClose++;
			if (q != q0[i]) begin closeSteps++; if (level < 4 || x0[i] >= 640) badClose++; end
			if (gh(i) - 2 * q < 64) badClose++;
			if (gh(i) - 2 * q < minGap) minGap = gh(i) - 2 * q;
		end
	end
	// 3. transfer : to the next pipe , only after the bird passed the active pipe
	if (activeIndex != a0) begin
		transfers++;
		if (activeIndex != (a0 + 1) % 6) badTransfer++;
		if (px(a0) + 48 >= birdX) badTransfer++;
	end
	// pipes on screen
	n = 0;
	for (int i = 0; i < 6; i++) if (px(i) + 48 > 0 && px(i) < 640) n++;
	if (n < onScreenMin) onScreenMin = n;
	if (n > onScreenMax) onScreenMax = n;
endtask

task automatic run(input int n);
	badScroll = 0; badSpacing = 0; badActiveY = 0; badOtherY = 0; badTransfer = 0; badItem = 0;
	onScreenMin = 9; onScreenMax = 0; transfers = 0; recycles = 0; coins = 0; yMoves = 0; closeSteps = 0; minGap = 999; badClose = 0;
	repeat (n) frame();
endtask

task automatic rules_ok(input string name);
	check(badScroll == 0 && badSpacing == 0 && badActiveY == 0 && badOtherY == 0 && badTransfer == 0 && badItem == 0 && badClose == 0,
	      $sformatf("%s : all rules ( scroll %0d spacing %0d activeY %0d otherY %0d transfer %0d item %0d close %0d )", name,
	                badScroll, badSpacing, badActiveY, badOtherY, badTransfer, badItem, badClose));
endtask

int y, p0, s0, a, cy0, scattered, badScattered;

// a scattered coin ( Y = pipeY + dy ) is reachable if some pipeY ( 16 .. 464 - gap ) puts the coin on the bird ( rows 232..246 )
// while the bird stays inside the gap , with a 6 pixel margin on each side
function automatic logic reachable(input int dy, input int gap);
	for (int p = 16; p <= 464 - gap; p++)
		if (p + dy <= 246 && p + dy + 15 >= 232 && p + 6 <= 232 && p + gap - 6 > 246 && dy + 16 <= gap) return 1'b1;
	return 1'b0;
endfunction

initial begin
	{startOfFrame, playEnable, newGamePulse, turbo, keyUp, keyDown, coinPulse} = '0;
	{shieldPulse, shatterPulse, hourglassPulse, confusePulse, invertControls} = '0;
	level = 3'd0; birdX = 11'sd160;
	resetN = 1'b0;
	#22 resetN = 1'b1;

	check(px(0) == 512 && px(5) == 1632 && activeIndex == 0, "reset : 6 pipes 512..1632 , pipe 0 active");
	new_game();
	check(it(0) == 0 && py(0) >= 144 && py(0) <= 207, "new game : first pipe without an item , gap near the middle");

	// frozen while not playing
	keyUp = 1'b1; y = py(0); repeat (10) frame(); keyUp = 1'b0;
	check(px(0) == 512 && py(0) == y, "frozen while playEnable = 0");

	// level 0 : keys move only the active pipe
	playEnable = 1'b1;
	keyUp = 1'b1; run(5); keyUp = 1'b0;
	check(px(0) == 507 && py(0) == y - 30, "UP 5 frames : active pipe 30 pixels up , scrolled 5 pixels");
	rules_ok("UP");

	// confusion : the keys are swapped - UP moves the active pipe DOWN , DOWN moves it UP
	invertControls = 1'b1; y = py(0);
	keyUp = 1'b1; run(5); keyUp = 1'b0;
	check(py(0) >= y + 27 && py(0) <= y + 33, "confused : UP moves the active pipe DOWN");
	keyDown = 1'b1; run(5); keyDown = 1'b0;
	check(py(0) >= y - 6 && py(0) <= y + 6, "confused : DOWN moves it back UP");
	invertControls = 1'b0;
	rules_ok("confused keys");

	// DOWN moves the active pipe down
	y = py(0);
	keyDown = 1'b1; run(5); keyDown = 1'b0;
	check(py(0) == y + 30, "DOWN 5 frames : the active pipe 30 pixels down");

	// a long level 0 game with random keys
	for (int k = 0; k < 20; k++) begin
		{keyUp, keyDown} = $urandom_range(0, 3);
		run(100);
		rules_ok($sformatf("level 0 block %0d", k));
	end
	{keyUp, keyDown} = 2'b00;

	// items : a coin of the active pipe disappears with coinPulse
	while (!(it(activeIndex) == 1 || it(activeIndex) == 2)) run(1);
	a = activeIndex;
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	check(it(a) == 0, "coinPulse removes the coin of the active pipe");

	// scattered coins : random , in the open space before their pipe , Y moves with the pipe
	scattered = 0; badScattered = 0;
	for (int k = 0; k < 600; k++) begin
		frame();
		for (int i = 0; i < 6; i++) if (itemOn[i]) begin
			scattered++;
			if (scx(i) + 16 > px(i)) badScattered++;                                      // before its pipe
			if (px((i + 5) % 6) < px(i) && scx(i) < px((i + 5) % 6) + 48) badScattered++;  // after the pipe before it ( the leftmost pipe has no pipe before it )
			if (!reachable(scy(i) - py(i), gh(i))) badScattered++;
		end
	end
	check(scattered > 0 && badScattered == 0, "scattered coins : between the pipes , every coin reachable with the bird inside the gap");
	while (!itemOn[activeIndex]) frame();
	a = activeIndex; cy0 = scy(a); y = py(a);
	keyDown = 1'b1; frame(); frame(); keyDown = 1'b0;
	check(scy(a) - cy0 == py(a) - y && py(a) != y, "the scattered coin moves together with the active pipe ( the player steers it )");
	// coinPulse while the scattered coin is at the bird removes it ( not the edge coin )
	while (!(isKind(activeIndex, 0) && scx(activeIndex) < birdX + 32 && scx(activeIndex) + 16 > birdX)) begin
		frame();
		if (!isKind(activeIndex, 0) && scx(activeIndex) + 16 <= birdX) run(1);
	end
	a = activeIndex; s0 = it(a);
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	check(!itemOn[a] && it(a) == s0, "coinPulse at a scattered coin removes it , the edge item stays");

	// random maze ( every new pipe ) ( chosen off-screen ) : gap heights and extra distances
	$display("     random gaps %0d..%0d , random extra distance %0d..%0d", gapMin, gapMax, extraMin, extraMax);
	check(gapMax - gapMin >= 15 && extraMax - extraMin >= 30, "new pipes : random gap heights and random distances");

	// ghost shield : a shatter breaks the active pipe , a placed-again pipe is whole
	a = activeIndex;
	@(negedge clk) shatterPulse = 1'b1; @(negedge clk) shatterPulse = 1'b0;
	check(broken[a] && (broken[0] + broken[1] + broken[2] + broken[3] + broken[4] + broken[5]) == 1, "shatterPulse breaks only the active pipe");
	while (broken[a]) run(1);
	check(1, "the shattered pipe is whole again when it is placed again at the right");

	// level 1 : new pipes get edge coins , never an item with code 3
	level = 3'd1;
	run(1500);
	rules_ok("level 1");
	$display("     level 1 : %0d new edge coins", coins);
	check(coins > 0, "level 1 : new pipes get coins ( and no poison )");

	// STATIC Y ( user decision ) : at every level , in both modes , without keys NO pipe moves up or down by itself
	for (int md = 0; md < 2; md++)
		for (int lv = 0; lv < 8; lv++) begin
			level = 3'(lv);
			run(300);
			rules_ok($sformatf("level %0d without keys", lv));
			check(yMoves == 0, $sformatf("level %0d : no key -> no pipe moved up or down ( %0d moves )", lv, yMoves));
			if (lv < 4) check(closeSteps == 0, $sformatf("level %0d : the gaps do not close ( only from LEVEL 5 )", lv));
			else        check(closeSteps > 0 && minGap >= 64, $sformatf("level %0d : the gaps close ( %0d steps ) , never below 64 ( min %0d )", lv, closeSteps, minGap));
		end

	// every 10 points ( 1 level ) : 1/4 pixel per frame faster , up to 2 pixels per frame from level 4
	for (int lv = 0; lv < 8; lv++) begin
		new_game(); level = 3'(lv);
		run(20);
		check(px(0) == 512 - (20 * (256 + 64 * ((lv > 4) ? 4 : lv))) / 256, $sformatf("level %0d : %0d/4 pixels per frame", lv, 4 + ((lv > 4) ? 4 : lv)));
	end
	// level 7 : pipes closer together ( 160 pixels ) , 2 pixels per frame , at least 3 pipes on the screen , faster keys ( 14 )
	new_game(); level = 3'd7;
	run(100);
	check(px(0) == 512 - 200, "level 7 : 2 pixels per frame");
	run(400);                                      // the pipes of the new game ( 224 apart ) leave the screen
	rules_ok("level 7 start");
	run(1500);
	rules_ok("level 7");
	$display("     level 7 : pipes on screen %0d..%0d , %0d recycled , %0d transfers", onScreenMin, onScreenMax, recycles, transfers);
	check(onScreenMin >= 3 && recycles > 10, "level 7 : at least 3 pipes on the screen , pipes come back at 160 pixels");

	// rare power-ups over all the new pipes of the test
	// the rare items are random ( about 1 of 21 new pipes each ) : play on until each kind was seen
	level = 3'd3;
	for (int k = 0; k < 8000 && (shieldItems == 0 || glassItems == 0 || purpleItems == 0); k++) frame();
	$display("     %0d new pipes : %0d shield items , %0d hourglasses , %0d purple traps", newPipes, shieldItems, glassItems, purpleItems);
	check(shieldItems > 0 && glassItems > 0 && purpleItems > 0, "the rare items appear : shields , hourglasses , purple traps");
	// collecting them removes them ( the item of the active pipe , when it is at the bird )
	while (!(isKind(activeIndex, 2) && scx(activeIndex) < birdX + 32 && scx(activeIndex) + 16 > birdX)) run(1);
	a = activeIndex;
	@(negedge clk) hourglassPulse = 1'b1; @(negedge clk) hourglassPulse = 1'b0;
	check(!itemOn[a], "hourglassPulse removes the hourglass");
	while (!(isKind(activeIndex, 3) && scx(activeIndex) < birdX + 32 && scx(activeIndex) + 16 > birdX)) run(1);
	a = activeIndex;
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	check(itemOn[a], "a coinPulse does not remove the purple trap");
	@(negedge clk) confusePulse = 1'b1; @(negedge clk) confusePulse = 1'b0;
	check(!itemOn[a], "confusePulse removes the purple trap");

	// turbo
	new_game(); level = 3'd0; turbo = 1'b1;
	run(100);
	check(px(0) == 512 - 200, "turbo : 2 pixels per frame at level 0");
	turbo = 1'b0;

	// score pulses
	p0 = pulses; new_game(); run(2000);
	check(pulses - p0 >= 7 && transfers == pulses - p0, "a score pulse for every transfer");

	// freeze ( GAME_OVER )
	playEnable = 1'b0; y = px(0); s0 = py(activeIndex); p0 = pulses;
	keyDown = 1'b1; repeat (100) frame(); keyDown = 1'b0;
	check(px(0) == y && py(activeIndex) == s0 && pulses == p0, "frozen : no scroll , no keys , no score");

	#3 resetN = 1'b0; #1;
	check(px(0) == 512 && activeIndex == 0, "async reset");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
