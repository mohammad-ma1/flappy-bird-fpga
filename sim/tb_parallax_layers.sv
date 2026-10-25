// self checking testbench for parallax_layers
//   far +1 every 4 frames , mid +1 every 2 frames , near +1 every frame , frozen without runEnable
`timescale 1ns/1ps

module tb_parallax_layers;

logic clk = 1'b0;
logic resetN, startOfFrame, runEnable;
logic [9:0]  farOffset;
logic [8:0]  midOffset;
logic [7:0]  nearOffset;

int errors = 0;
int checks = 0;
int f0, m0, n0;

always #5 clk = ~clk;

parallax_layers dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

task automatic frame();
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
	repeat (3) @(negedge clk);
endtask

initial begin
	{startOfFrame, runEnable} = '0;
	resetN = 1'b0;
	#22 resetN = 1'b1;
	runEnable = 1'b1;

	check(farOffset == 0 && midOffset == 0 && nearOffset == 0, "reset : offsets 0");
	repeat (400) frame();
	check(nearOffset == 8'(400), "near layer ( clouds ) : 1 pixel every frame");
	check(midOffset  == 9'd200,  "mid layer ( skyline ) : 1 pixel every 2 frames");
	check(farOffset  == 10'd100, "far layer ( stars ) : 1 pixel every 4 frames");

	// frozen without runEnable ( GAME OVER )
	runEnable = 1'b0;
	f0 = farOffset; m0 = midOffset; n0 = nearOffset;
	repeat (20) frame();
	check(farOffset == f0 && midOffset == m0 && nearOffset == n0, "frozen while runEnable is 0");

	#3 resetN = 1'b0; #1;
	check(nearOffset == 0 && farOffset == 0, "async reset");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
