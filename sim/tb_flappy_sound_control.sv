// self checking testbench for flappy_sound_control
`timescale 1ns/1ps

module tb_flappy_sound_control;

logic clk = 1'b0;
logic resetN, scorePulse, hitPulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse;
logic [2:0] level;
logic [3:0] melodySelect;
logic startMelody;

int errors = 0;
int checks = 0;
int highClocks;
int starts;              // rising edges of startMelody
logic [3:0] startSong;   // the song at the last rising edge
logic startMelody_d = 1'b0;

always #5 clk = ~clk;
always @(posedge clk) begin
	if (startMelody) highClocks++;
	if (startMelody && !startMelody_d) begin starts++; startSong = melodySelect; end
	startMelody_d <= startMelody;
end

flappy_sound_control dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s (select=%0d start=%b starts=%0d)", what, melodySelect, startMelody, starts); end
endtask

initial begin
	{scorePulse, hitPulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse} = '0; level = 3'd0;
	resetN = 1'b0;
	#22 resetN = 1'b1;
	repeat (40) @(negedge clk);
	check(!startMelody, "no sound after reset");

	// score : the song starts 2 clocks after the pulse ( 1 clock alignment + 1 clock register )
	highClocks = 0; starts = 0;
	@(negedge clk) scorePulse = 1'b1;
	@(negedge clk) scorePulse = 1'b0;
	@(negedge clk);
	check(startMelody && melodySelect == 4'd5, "score -> song 5 starts");
	repeat (40) @(negedge clk);
	check(!startMelody && highClocks == 16 && starts == 1, "one start pulse of 16 clocks");
	check(melodySelect == 4'd5, "the song number is held after the start pulse");

	// a pass that levels up : the level changes one clock after the score pulse ( like game_controller )
	starts = 0;
	@(negedge clk) scorePulse = 1'b1;
	@(negedge clk) begin scorePulse = 1'b0; level = 3'd1; end
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd0 && melodySelect == 4'd0, "level up : one clean start of song 0 ( not the score song )");

	// crash and score in the same clock ( the level also changes ) : the crash song wins
	starts = 0;
	@(negedge clk) begin hitPulse = 1'b1; scorePulse = 1'b1; end
	@(negedge clk) begin hitPulse = 1'b0; scorePulse = 1'b0; level = 3'd2; end
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd3 && melodySelect == 4'd3, "crash : one clean start of song 3");

	// coin -> song 4 , a shield wins over a coin in the same clock
	starts = 0;
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd4, "coin : song 4");
	starts = 0;
	@(negedge clk) {coinPulse, shieldPulse} = 2'b11; @(negedge clk) {coinPulse, shieldPulse} = 2'b00;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd0, "shield ( with a coin ) : song 0");

	// shield -> song 0 , shatter -> song 3 , shatter wins over a shield in the same clock
	starts = 0;
	@(negedge clk) shieldPulse = 1'b1; @(negedge clk) shieldPulse = 1'b0;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd0, "shield item : song 0");
	starts = 0;
	@(negedge clk) {shatterPulse, shieldPulse} = 2'b11; @(negedge clk) {shatterPulse, shieldPulse} = 2'b00;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd3, "shatter ( with a shield ) : song 3");
	starts = 0;
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	repeat (40) @(negedge clk);

	// hourglass -> song 0 , purple trap -> song 2 ( it wins over a shield in the same clock )
	starts = 0;
	@(negedge clk) hourglassPulse = 1'b1; @(negedge clk) hourglassPulse = 1'b0;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd0, "hourglass : song 0");
	starts = 0;
	@(negedge clk) {confusePulse, shieldPulse} = 2'b11; @(negedge clk) {confusePulse, shieldPulse} = 2'b00;
	repeat (40) @(negedge clk);
	check(starts == 1 && startSong == 4'd2, "purple trap ( with a shield ) : song 2");
	@(negedge clk) coinPulse = 1'b1; @(negedge clk) coinPulse = 1'b0;
	repeat (40) @(negedge clk);

	// a new game sets the level back to 0 : no sound
	starts = 0;
	level = 3'd0;
	repeat (40) @(negedge clk);
	check(starts == 0 && melodySelect == 4'd4, "level back to 0 is not a level up");

	#3 resetN = 1'b0; #1;
	check(!startMelody, "async reset");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
