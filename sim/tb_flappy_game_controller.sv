// self checking testbench for flappy_game_controller
`timescale 1ns/1ps

module tb_flappy_game_controller;

logic clk = 1'b0;
logic [3:0] msgId;
logic resetN, startOfFrame, startKey, hitPulse, scorePulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse, cheatNoDeath;
logic [1:0]  gameState;
logic        playEnable, newGamePulse, nightMode, shieldActive, slowMoActive, invertControls;
logic [15:0] scoreBCD, highScoreBCD;
logic [2:0]  level;
logic [8:0]  dayStep;
logic        pipesVisible;
int d0, hidden, longestHidden, run;

int errors = 0;
int checks = 0;
int newGames = 0;

always #5 clk = ~clk;
always @(posedge clk) begin
	if (newGamePulse) newGames++;
end

flappy_game_controller dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s (state=%0d score=%h best=%h level=%0d)",
	                                  what, gameState, scoreBCD, highScoreBCD, level); end
endtask

task automatic frame();                 // a short frame : the controller only counts startOfFrame
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
	@(negedge clk);
endtask
task automatic frames(input int n); repeat (n) frame(); endtask

task automatic pulse_score(); @(negedge clk) scorePulse = 1'b1;  @(negedge clk) scorePulse = 1'b0;  endtask
task automatic pulse_coin();  @(negedge clk) coinPulse = 1'b1;   @(negedge clk) coinPulse = 1'b0;   endtask
task automatic pulse_hit();   @(negedge clk) hitPulse = 1'b1;    @(negedge clk) hitPulse = 1'b0;    endtask

task automatic press_start();
	@(negedge clk) startKey = 1'b1;
	repeat (3) @(negedge clk);
	startKey = 1'b0;
	@(negedge clk);
endtask

function automatic int bcd(input logic [15:0] v);
	return v[15:12]*1000 + v[11:8]*100 + v[7:4]*10 + v[3:0];
endfunction


initial begin
	{startOfFrame, startKey, hitPulse, scorePulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse, cheatNoDeath} = '0;
	resetN = 1'b0;
	#22 resetN = 1'b1;

	check(gameState == 2'd0 && !playEnable, "reset -> START");
	pulse_score(); pulse_hit();
	check(gameState == 2'd0 && scoreBCD == 0, "START ignores score , hit");

	// ---- NORMAL game
	press_start();
	check(gameState == 2'd1 && playEnable && newGames == 1, "ENTER : PLAY , one newGamePulse");

	// score : +1 pipe , +2 coin , +3 both in the same clock
	pulse_score();  check(scoreBCD == 16'h0001 && !nightMode, "pipe +1 , no night mode");
	pulse_coin();   check(scoreBCD == 16'h0003, "coin +2");
	@(negedge clk) {scorePulse, coinPulse} = 2'b11;
	@(negedge clk) {scorePulse, coinPulse} = 2'b00;
	check(scoreBCD == 16'h0006, "pipe + coin together +3");
	check(level == 3'd0, "6 points : still level 0 ( a level every 10 points )");

	repeat (3) pulse_score();                        // 9
	pulse_coin();                                    // 11
	check(scoreBCD == 16'h0011, "9 + coin = 11");
	// night mode : on at 15 , then exactly 5 seconds ( 365 frames ) - passing pipes or coins does not end it
	repeat (3) pulse_score();                        // 14
	check(!nightMode, "no night mode at 14");
	pulse_score();                                   // 15
	check(nightMode, "night mode at 15 ( every 15 points )");
	pulse_score(); pulse_coin();                     // 18 : a pipe and a coin in the dark
	check(nightMode, "passing a pipe does not end the night mode any more");
	frames(364);
	check(nightMode, "still night after 364 frames");
	frame();
	check(!nightMode, "day again after 365 frames ( exactly 5 seconds )");
	repeat (2) pulse_score();                        // 20
	pulse_coin();                                    // 22
	check(scoreBCD == 16'h0022 && !nightMode, "no night mode at 20 .. 22");
	repeat (8) pulse_score();                        // 30
	check(scoreBCD == 16'h0030 && nightMode, "night mode again at 30");
	frames(365);
	check(!nightMode, "5 seconds later : day again");
	repeat (14) pulse_score();                       // 44
	check(!nightMode, "no night mode at 44");
	pulse_score();                                   // 45
	check(nightMode, "night mode at 45");
	repeat (54) pulse_score();                       // 99 -> 100 BCD carry
	pulse_score();
	check(scoreBCD == 16'h0100, "BCD carry 99 -> 100");
	check(level == 3'd7, "level saturates at 7");

	// ghost shield : 10 seconds = 730 frames , a shatter consumes it at once
	@(negedge clk) shieldPulse = 1'b1; @(negedge clk) shieldPulse = 1'b0;
	check(shieldActive, "shield item : shield on");
	frames(729);
	check(shieldActive, "still shielded after 729 frames");
	frame();
	check(!shieldActive, "shield off after 730 frames ( 10 seconds )");
	@(negedge clk) shieldPulse = 1'b1; @(negedge clk) shieldPulse = 1'b0;
	frames(100);
	@(negedge clk) shatterPulse = 1'b1; @(negedge clk) shatterPulse = 1'b0;
	check(!shieldActive && gameState == 2'd1, "a shatter consumes the shield , the game goes on");
	@(negedge clk) shieldPulse = 1'b1; @(negedge clk) shieldPulse = 1'b0;

	// hourglass : 10 seconds = 730 frames of slow motion , independent of the shield
	@(negedge clk) hourglassPulse = 1'b1; @(negedge clk) hourglassPulse = 1'b0;
	check(slowMoActive, "hourglass : slow motion on");
	frames(729);
	check(slowMoActive, "still slow after 729 frames");
	frame();
	check(!slowMoActive, "slow motion off after 730 frames ( 10 seconds )");

	// purple trap : 7 seconds = 511 frames of swapped keys , touching it again restarts the 7 seconds
	@(negedge clk) confusePulse = 1'b1; @(negedge clk) confusePulse = 1'b0;
	check(invertControls, "purple trap : the keys are swapped");
	frames(510);
	check(invertControls, "still swapped after 510 frames");
	frame();
	check(!invertControls, "back to normal after 511 frames ( 7 seconds )");
	@(negedge clk) confusePulse = 1'b1; @(negedge clk) confusePulse = 1'b0;
	frames(400);
	@(negedge clk) confusePulse = 1'b1; @(negedge clk) confusePulse = 1'b0;
	frames(400);
	check(invertControls, "a second purple trap restarts the 7 seconds");
	@(negedge clk) hourglassPulse = 1'b1; @(negedge clk) hourglassPulse = 1'b0;

	// the day / night cycle : +1 every frame
	d0 = dut.dayCycle;
	frames(100);
	check(dut.dayCycle == 12'(d0 + 100) && dayStep == dut.dayCycle[11:3], "day / night cycle : +1 every frame");
	// the invisible maze ( level 7 here ) : in every 1825 frames ( 25 s ) the pipes are invisible 73 frames ( 1 s ) in one piece - rare
	hidden = 0; longestHidden = 0; run = 0;
	repeat (2 * 1825) begin
		frame();
		if (!pipesVisible) begin hidden++; run++; if (run > longestHidden) longestHidden = run; end else run = 0;
	end
	check(hidden == 2 * 73 && longestHidden == 73, $sformatf("invisible maze : 1 s invisible once every 25 s ( %0d hidden frames , longest %0d )", hidden, longestHidden));

	// cheat : no death
	cheatNoDeath = 1'b1; pulse_hit();
	check(gameState == 2'd1, "cheatNoDeath ignores a lethal hit");
	cheatNoDeath = 1'b0;

	// lethal hit ( with a score pulse in the same clock - not counted )
	@(negedge clk) {hitPulse, scorePulse} = 2'b11;
	@(negedge clk) {hitPulse, scorePulse} = 2'b00;
	check(gameState == 2'd2 && !playEnable, "lethal hit -> GAME_OVER");
	check(scoreBCD == 16'h0100 && highScoreBCD == 16'h0100, "final score kept , high score updated");
	check(!shieldActive, "GAME_OVER clears the shield");
	check(!slowMoActive && !invertControls, "GAME_OVER clears the slow motion and the swapped keys");

	// restart lock
	press_start();
	check(gameState == 2'd2, "restart blocked before GAME_OVER_FRAMES");
	frames(60);

	// ---- the level comes ONLY from the score ( every 10 points ) : no level up by time , and no blinking below level 4
	hidden = 0;
	press_start();
	check(gameState == 2'd1 && scoreBCD == 0 && level == 0 && newGames == 2 && !nightMode, "restart : score 0 , level 0 , no night mode");
	repeat (40*73) begin frame(); if (!pipesVisible) hidden++; end
	check(level == 3'd0, "level 0 after 40 seconds without points ( the level comes only from the score )");
	check(hidden == 0, "level 0 : the pipes never blink invisible ( only from level 3 = score 30 )");
	repeat (9) pulse_score();
	check(scoreBCD == 16'h0009 && level == 3'd0, "score 9 : still level 0 ( LEVEL 1 on the screen )");
	pulse_score();
	check(scoreBCD == 16'h0010 && level == 3'd1, "score 10 : level 1 ( every 10 points )");
	repeat (8) pulse_score(); pulse_coin();          // 20 , reached with a coin
	check(scoreBCD == 16'h0020 && level == 3'd2, "score 20 : level 2 ( also when a coin jumps to it )");
	pulse_hit(); frames(60);

	// ---- no time limit : a game goes on as long as the bird lives
	press_start();
	frames(73*61);
	check(gameState == 2'd1, "no time limit : still playing after 61 seconds");

	#3 resetN = 1'b0; #1;
	check(gameState == 2'd0 && scoreBCD == 0 && highScoreBCD == 0, "async reset");

	// ---- EVENT MESSAGES ( msgId , 2 seconds = 146 frames )
	cheatNoDeath = 1'b0;
	#6 resetN = 1'b1;
	if (gameState == 2'd1) pulse_hit();
	frames(70);                                      // past the GAME OVER restart lock
	check(msgId == 4'd0, "messages : none outside the game");
	press_start();
	check(msgId == 4'd1, "message : GO! when a game starts");
	frames(146);
	check(msgId == 4'd0, "message : gone after 2 seconds");
	repeat (10) pulse_score();
	check(level == 3'd1 && msgId == 4'd2, "message : score 10 -> LEVEL 2! FASTER PIPES");
	frames(146);
	repeat (20) pulse_score();
	check(level == 3'd3 && msgId == 4'd3, "message : score 30 -> INVISIBLE MAZE! ( level 4 on the screen )");
	frames(146);
	check(msgId == 4'd6 && nightMode, "message : the night mode of score 30 waits , then NIGHT MODE!");
	frames(146);
	check(msgId == 4'd0, "message : nothing waits any more");
	repeat (10) pulse_score();
	check(level == 3'd4 && msgId == 4'd4, "message : score 40 -> CLOSING PIPES! ( level 5 on the screen )");
	@(negedge clk) shieldPulse = 1'b1;    @(negedge clk) shieldPulse = 1'b0;
	check(msgId == 4'd7, "message : a newer event replaces it : SHIELD!");
	@(negedge clk) hourglassPulse = 1'b1; @(negedge clk) hourglassPulse = 1'b0;
	check(msgId == 4'd8, "message : SLOW MOTION!");
	@(negedge clk) confusePulse = 1'b1;   @(negedge clk) confusePulse = 1'b0;
	check(msgId == 4'd9, "message : REVERSED KEYS!");
	@(negedge clk) shatterPulse = 1'b1;   @(negedge clk) shatterPulse = 1'b0;
	check(msgId == 4'd10, "message : PIPE BROKEN!");
	repeat (20) pulse_score();
	check(level == 3'd6 && msgId == 4'd5, "message : score 60 -> LEVEL 7! KEEP GOING! ( top speed )");
	pulse_hit();
	check(gameState == 2'd2 && msgId == 4'd0, "message : cleared at GAME OVER");
	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
