// self checking testbench for flappy_bird_logic ( fixed bird , only the wings move )
`timescale 1ns/1ps

module tb_flappy_bird_logic;

logic clk = 1'b0;
logic resetN, startOfFrame, playEnable, newGamePulse;
logic signed [10:0] topLeftX, topLeftY;
logic flapFrame;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_bird_logic dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s (X=%0d Y=%0d wing=%b)", what, topLeftX, topLeftY, flapFrame); end
endtask

task automatic frame();
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
	repeat (14) @(negedge clk);
endtask

int moved, changes;
logic prevWing;
task automatic run(input int n);
	moved = 0; changes = 0; prevWing = flapFrame;
	repeat (n) begin
		frame();
		if (topLeftX != 160 || topLeftY != 224) moved++;
		if (flapFrame != prevWing) changes++;
		prevWing = flapFrame;
	end
endtask

initial begin
	{startOfFrame, playEnable, newGamePulse} = '0;
	resetN = 1'b0;
	#22 resetN = 1'b1;

	check(topLeftX == 160 && topLeftY == 224 && flapFrame == 1'b0, "reset : bird at (160,224) , wings up");

	run(100);
	check(moved == 0 && changes == 0, "not playing : the bird and the wings do not move");

	playEnable = 1'b1;
	run(800);
	check(moved == 0, "playing 800 frames : the bird stays at (160,224)");
	check(changes == 100, $sformatf("playing : the wings change every 8 frames (%0d changes)", changes));

	@(negedge clk) newGamePulse = 1'b1;
	@(negedge clk) newGamePulse = 1'b0;
	check(flapFrame == 1'b0 && topLeftY == 224, "new game : wings up , same place");

	#3 resetN = 1'b0; #1;
	check(flapFrame == 1'b0, "async reset");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
