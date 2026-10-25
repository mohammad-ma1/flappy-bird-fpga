// a short game for the report waveform of flappy_game_controller ( not a self checking test )
// START -> ENTER -> PLAY -> 10 points ( level up ) -> a coin -> hit -> GAME_OVER -> wait -> ENTER -> PLAY
// every clock the main signals are written to sim/out/wave_game_controller.csv
`timescale 1ns/1ps

module tb_wave_game_controller;

logic clk = 1'b0;
logic resetN, startOfFrame, startKey, hitPulse, scorePulse, coinPulse;
logic shieldPulse, shatterPulse, hourglassPulse, confusePulse, cheatNoDeath;
logic [1:0]  gameState;
logic        playEnable, newGamePulse, shieldActive, slowMoActive, invertControls, nightMode, pipesVisible;
logic [15:0] scoreBCD, highScoreBCD;
logic [2:0]  level;
logic [8:0]  dayStep;
logic [3:0]  msgId;

always #5 clk = ~clk;

flappy_game_controller dut (.*);

int fd, t = 0;
always @(posedge clk) begin
	#1;
	$fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d,%0d\n", t, resetN, startKey, startOfFrame, scorePulse, coinPulse, hitPulse,
	        scoreBCD, level, gameState, newGamePulse);
	t++;
end

task automatic frame(); @(negedge clk) startOfFrame = 1'b1; @(negedge clk) startOfFrame = 1'b0; endtask
task automatic frames(input int n); repeat (n) frame(); endtask

initial begin
	fd = $fopen("wave_game_controller.csv", "w");
	$fwrite(fd, "t,resetN,startKey,startOfFrame,scorePulse,coinPulse,hitPulse,scoreBCD,level,gameState,newGamePulse\n");
	{startOfFrame, startKey, hitPulse, scorePulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse, cheatNoDeath} = '0;
	resetN = 1'b0;
	repeat (3) @(negedge clk);
	resetN = 1'b1;
	frames(3);
	// ENTER : START -> PLAY
	@(negedge clk) startKey = 1'b1; repeat (4) @(negedge clk); startKey = 1'b0;
	frames(2);
	// 10 pipes : the score goes up to 10 , the level becomes 1
	repeat (10) begin @(negedge clk) scorePulse = 1'b1; @(negedge clk) scorePulse = 1'b0; frame(); end
	// a coin : +2
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	frames(3);
	// a hit : PLAY -> GAME_OVER
	@(negedge clk) hitPulse = 1'b1; @(negedge clk) hitPulse = 1'b0;
	frames(2);
	// ENTER too early ( before 60 frames ) : ignored
	@(negedge clk) startKey = 1'b1; repeat (4) @(negedge clk); startKey = 1'b0;
	frames(60);
	// ENTER after 60 frames : a new game
	@(negedge clk) startKey = 1'b1; repeat (4) @(negedge clk); startKey = 1'b0;
	frames(4);
	$fclose(fd);
	$finish;
end

endmodule
