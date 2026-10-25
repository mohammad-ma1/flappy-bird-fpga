// self checking testbench for pipes_draw
// streams full frames ( one pixel per clock ) and checks every pixel 2 clocks later against a reference model
`timescale 1ns/1ps

module tb_pipes_draw;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY;
logic signed [11:0] pipeX     [0:5];
logic        [8:0]  gapTop    [0:5];
logic        [8:0]  gapBottom [0:5];
logic               broken    [0:5];
logic [2:0]  activeIndex;
int sq = 0;                       // the crushing pipes : every tube this many pixels closer to the middle
logic        drawingRequest;
logic [7:0]  RGBout;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

pipes_draw dut (.*);

// the model pipes ( m = model )
int mX [0:5];
int mY [0:5];
int mGapH [0:5] = '{128, 128, 128, 128, 128, 128};
int mBroken [0:5] = '{0, 0, 0, 0, 0, 0};

task automatic set_pipes(input int x0, x1, x2, x3, input int y0, y1, y2, y3, input int act, input int b);
	mX[0] = x0; mX[1] = x1; mX[2] = x2; mX[3] = x3; mX[4] = 1500; mX[5] = 1700;
	mY[0] = y0; mY[1] = y1; mY[2] = y2; mY[3] = y3; mY[4] = 100; mY[5] = 100;
	drive();
	activeIndex = 3'(act);
endtask

// the inputs of the DUT from the model pipes
task automatic drive();
	for (int i = 0; i < 6; i++) begin
		pipeX[i]     = 12'(mX[i]);
		gapTop[i]    = 9'(mY[i] + sq);
		gapBottom[i] = 9'(mY[i] + mGapH[i] - sq);
		broken[i]    = (mBroken[i] != 0);
	end
endtask

// reference model of one pixel ( gap = 128 , width 48 , caps 16 , body inset 4 , shade 10 , the active pipe is teal , no breathing )
function automatic logic [7:0] model(input int x, y);
	int ix, top, bot, left, right;
	logic cap, outline, act;
	for (int i = 0; i < 6; i++) begin
		ix = x - mX[i];
		if (ix < 0 || ix > 47 || mBroken[i] != 0) continue;                    // a broken pipe is not drawn
		top = mY[i] + sq; bot = mY[i] + mGapH[i] - sq;           // the crushing pipes
		if (y >= top && y < bot) return 8'hFF;                          // the fixed gap
		cap = (y < top && y >= top - 16) || (y >= bot && y < bot + 16);
		left  = cap ? 0 : 4;
		right = cap ? 47 : 43;
		if (ix < left || ix > right) return 8'hFF;
		outline = (ix == left) || (ix == right) || (cap && (y == top - 1 || y == top - 16 || y == bot || y == bot + 15));
		act = (i == activeIndex);
		if (outline)          return act ? 8'h05 : 8'h04;
		if (ix < left + 10)   return act ? 8'h5F : 8'h9D;
		if (ix > right - 10)  return act ? 8'h0A : 8'h0C;
		return act ? 8'h16 : 8'h18;
	end
	return 8'hFF;
endfunction

logic [7:0] exp_q[$];
int colDrawn [0:639];

task automatic compare(input string name);
	logic [7:0] e;
	e = exp_q.pop_front();
	checks++;
	if (RGBout !== e || drawingRequest !== (e != 8'hFF)) begin
		errors++;
		if (errors < 10) $display("FAIL %s : RGB %h DR %b expected %h", name, RGBout, drawingRequest, e);
	end
endtask

task automatic scan_frame(input string name);
	int drawn = 0;
	for (int x = 0; x < 640; x++) colDrawn[x] = 0;
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 640; x++) begin
			@(negedge clk);
			if (exp_q.size() == 2) compare(name);
			if (drawingRequest && x >= 2) colDrawn[x-2]++;
			pixelX = 11'(x); pixelY = 11'(y);
			exp_q.push_back(model(x, y));
		end
	repeat (2) begin @(negedge clk); compare(name); end
	for (int x = 0; x < 640; x++) drawn += colDrawn[x];
	$display("%s : %0d pixels drawn", name, drawn);
endtask

task automatic check_col(input int x, input int expected, input string what);
	checks++;
	if (colDrawn[x] != expected) begin errors++; $display("FAIL %s : column %0d has %0d pixels , expected %0d", what, x, colDrawn[x], expected); end
endtask

initial begin
	pixelX = 0; pixelY = 0;
	set_pipes(512, 736, 960, 1184, 176, 176, 176, 176, 0, 0);
	resetN = 1'b0;
	#22;
	checks++;
	if (drawingRequest !== 1'b0 || RGBout !== 8'hFF) begin errors++; $display("FAIL nothing drawn during reset"); end
	resetN = 1'b1;

	// 3 pipes on screen , pipe 1 active
	set_pipes(100, 324, 548, 772, 50, 200, 336, 16, 1, 0);
	scan_frame("3 pipes , pipe 1 active");
	check_col(100 + 20, 480 - 128, "pipe 0 body column : 480 - fixed gap");
	check_col(324 + 20, 480 - 128, "pipe 1 body column : 480 - fixed gap");
	check_col(548,      32,        "pipe 2 cap-only column : the two caps");
	check_col(200,      0,         "between pipes : nothing");

	// a pipe partly outside on the left ( negative X ) and gaps at the limits , pipe 3 active
	set_pipes(-30, 194, 418, 642, 16, 336, 100, 250, 3, 0);
	scan_frame("negative X , gaps at the limits");
	check_col(0,  480 - 128, "pipe 0 at X -30 is still drawn at the left edge");
	check_col(20, 0,         "pipe 0 ends at X 17");

	// static gaps : the active pipe has the same gap as the others ( no breathing )
	set_pipes(100, 324, 548, 772, 50, 200, 336, 16, 1, 0);
	scan_frame("active pipe , static gap");
	check_col(324 + 20, 480 - 128, "active pipe : gap 128 ( static )");
	check_col(100 + 20, 480 - 128, "other pipe : gap 128");

	// the crushing pipes : every tube 40 pixels closer to the middle ( gap 128 -> 48 )
	sq = 40; drive();
	scan_frame("crushing pipes ( 40 pixels per tube )");
	check_col(324 + 20, 480 - 48, "active pipe : gap 128 - 2 x 40 = 48");
	check_col(100 + 20, 480 - 48, "other pipe : gap 48");
	sq = 0; drive();

	// random gap heights ( 112 and 143 ) and a shattered pipe ( pipe 2 )
	mGapH = '{112, 143, 128, 128, 128, 128};
	mBroken = '{0, 0, 1, 0, 0, 0};
	set_pipes(100, 324, 548, 772, 50, 200, 336, 16, 3, 0);
	scan_frame("gaps 112 / 143 , pipe 2 shattered");
	check_col(100 + 20, 480 - 112, "pipe 0 : gap 112");
	check_col(324 + 20, 480 - 143, "pipe 1 : gap 143");
	check_col(548 + 20, 0,         "shattered pipe 2 : nothing drawn");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
