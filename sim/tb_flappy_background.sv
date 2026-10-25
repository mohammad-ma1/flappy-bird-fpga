// self checking testbench for flappy_background
// renders screen rows ( one pixel per clock , output taken 2 clocks later ) and checks the layers and the scenes of the levels ( day , sunset , night )
`timescale 1ns/1ps

module tb_flappy_background;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY;
logic [9:0] farOffset;
logic [8:0] midOffset;
logic [7:0] nearOffset;
logic [2:0] level;
logic startOfFrame;
logic [7:0] backGroundRGB;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_background dut (.*);

// the key colors : day , sunset , night ( reference )
logic [7:0] TOP_KEY    [0:2] = '{8'h53, 8'h8E, 8'h01};
logic [7:0] BOTTOM_KEY [0:2] = '{8'h7B, 8'hF6, 8'h06};
localparam int DAY = 0, NIGHT = 2;         // the levels of the day and the night scenes

// reference blend : every channel a + floor( ( b - a ) x f / 32 )
function automatic int ch(input int a, input int b, input int fr);
	int d;
	d = (b - a) * fr;
	return a + ((d >= 0) ? d / 32 : -((-d + 31) / 32));
endfunction
function automatic logic [7:0] ref_blend(input logic [7:0] a, input logic [7:0] b, input int fr);
	return { 3'(ch(a[7:5], b[7:5], fr)), 3'(ch(a[4:2], b[4:2], fr)), 2'(ch(a[1:0], b[1:0], fr)) };
endfunction
// the expected sky color of a level ( top = 1 : the upper band ) : level 0 day , 1 sunset , 2+ night
function automatic logic [7:0] ref_sky(input int lvl, input int top);
	int k;
	k = (lvl == 0) ? 0 : (lvl == 1) ? 1 : 2;
	return top ? TOP_KEY[k] : BOTTOM_KEY[k];
endfunction

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

// render one screen row into rowA / rowB
logic [7:0] rowA [0:639];
logic [7:0] rowB [0:639];
// s : the near ( clouds ) offset , the mid and far offsets are set apart ( m , f )
int m = 0, f = 0;
int curLevel = 0;
task automatic one_frame();
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
endtask
// a level and enough frames for the blend to end ( 1 + 32 x 2 frames )
task automatic set_scene(input int lvl);
	level = 3'(lvl);
	repeat (80) one_frame();
	curLevel = lvl;
endtask
// the color of one pixel ( 2 clocks latency )
task automatic sample_t(input int x, input int y, output logic [7:0] c);
	@(negedge clk) begin pixelX = 11'(x); pixelY = 11'(y); end
	repeat (3) @(negedge clk);
	c = backGroundRGB;
endtask
task automatic render(input int y, input int s, input int lvl, input logic toB);
	if (lvl != curLevel) set_scene(lvl);
	nearOffset = 8'(s); midOffset = 9'(m); farOffset = 10'(f);
	for (int x = 0; x < 640 + 2; x++) begin
		@(negedge clk);
		if (x >= 2) begin
			if (toB) rowB[x-2] = backGroundRGB; else rowA[x-2] = backGroundRGB;
		end
		pixelX = 11'(x < 640 ? x : 0); pixelY = 11'(y);
	end
endtask

function automatic int count(input logic toB, input logic [7:0] c);
	int n = 0;
	for (int x = 0; x < 640; x++) if ((toB ? rowB[x] : rowA[x]) == c) n++;
	return n;
endfunction

int n, ok, expectedCloud;

initial begin
	pixelX = 0; pixelY = 0; farOffset = 0; midOffset = 0; nearOffset = 0; level = 0; startOfFrame = 0;
	resetN = 1'b0;
	#22 resetN = 1'b1;

	// 2 clocks latency : the color changes 2 clocks after the pixel moves from the top band to the bottom band
	@(negedge clk) begin pixelX = 300; pixelY = 20; end
	repeat (3) @(negedge clk);
	check(backGroundRGB == TOP_KEY[0], "sky top band color ( day )");
	pixelY = 330;
	@(negedge clk) check(backGroundRGB == TOP_KEY[0], "latency : not changed after 1 clock");
	@(negedge clk) check(backGroundRGB == BOTTOM_KEY[0], "latency : changed after 2 clocks");

	// the scene of every level ( row 330 : below the clouds , above the buildings ; row 20 : the upper band , + stars at night )
	for (int lv = 0; lv < 8; lv++) begin
		render(330, 0, lv, 0);
		check(count(0, ref_sky(lv, 0)) == 640, $sformatf("level %0d : bottom sky %h on the whole row", lv, ref_sky(lv, 0)));
		render(20, 0, lv, 0);
		check(count(0, ref_sky(lv, 1)) + count(0, 8'hFE) == 640 && count(0, ref_sky(lv, 1)) > 600, $sformatf("level %0d : top sky %h ( + stars at night )", lv, ref_sky(lv, 1)));
	end
	check(ref_sky(0, 0) == 8'h7B && ref_sky(1, 0) == 8'hF6 && ref_sky(2, 0) == 8'h06, "level 1 day light blue , level 2 sunset orange , level 3 night dark blue");
	// a new level : the colors blend smoothly ( every channel changes by 1 at most per frame ) and reach the new key colors
	begin
		int maxStep, framesToEnd; logic [7:0] a, b;
		set_scene(0);
		level = 3'd1;                                       // score 10 : day -> sunset
		maxStep = 0; framesToEnd = -1;
		sample_t(300, 330, a);
		for (int fr = 0; fr < 100; fr++) begin
			one_frame();
			sample_t(300, 330, b);
			if ((a[7:5] > b[7:5] ? a[7:5] - b[7:5] : b[7:5] - a[7:5]) > maxStep) maxStep = (a[7:5] > b[7:5] ? a[7:5] - b[7:5] : b[7:5] - a[7:5]);
			if ((a[4:2] > b[4:2] ? a[4:2] - b[4:2] : b[4:2] - a[4:2]) > maxStep) maxStep = (a[4:2] > b[4:2] ? a[4:2] - b[4:2] : b[4:2] - a[4:2]);
			if ((a[1:0] > b[1:0] ? a[1:0] - b[1:0] : b[1:0] - a[1:0]) > maxStep) maxStep = (a[1:0] > b[1:0] ? a[1:0] - b[1:0] : b[1:0] - a[1:0]);
			if (b == 8'hF6 && framesToEnd < 0) framesToEnd = fr + 1;
			a = b;
		end
		$display("     day -> sunset : %0d frames , max change %0d per channel and frame", framesToEnd, maxStep);
		check(maxStep <= 1 && framesToEnd > 30 && framesToEnd <= 70 && a == 8'hF6, "a new level : a smooth blend ( about 1 s ) to the new scene");
		curLevel = 1;
	end

	// clouds : row 63 is a full row of the cloud bitmap ( 64 pixels wide ) , every 256 pixels
	render(63, 100, 0, 0);
	expectedCloud = 0;
	for (int x = 0; x < 640; x++) if (((x + 100) % 256) < 64) expectedCloud++;
	check(count(0, 8'hFE) == expectedCloud, $sformatf("clouds : %0d cloud pixels in a full cloud row", expectedCloud));

	// parallax : every layer moves only with its own offset
	render(63, 101, 0, 1);
	ok = 1;
	for (int x = 0; x < 639; x++) if (rowB[x] != rowA[x+1]) ok = 0;
	check(ok, "clouds : near offset + 1 -> 1 pixel left");
	m = 7; f = 9;
	render(63, 100, 0, 1);
	ok = 1;
	for (int x = 0; x < 640; x++) if (rowB[x] != rowA[x]) ok = 0;
	check(ok, "clouds do not move with the mid / far offsets");
	m = 0; f = 0;
	render(470, 100, 0, 0);
	m = 1;
	render(470, 140, 0, 1);
	ok = 1;
	for (int x = 0; x < 639; x++) if (rowB[x] != rowA[x+1]) ok = 0;
	check(ok, "buildings : mid offset + 1 -> 1 pixel left ( not with the near offset )");
	m = 0;
	// stars ( night ) : far offset + 1 -> 1 pixel left , not with the near / mid offsets
	begin
		int ys, okStar;
		okStar = 1;
		for (ys = 0; ys < 40; ys++) begin
			f = 0; m = 0; render(ys, 0, NIGHT, 0);
			f = 1; m = 5; render(ys, 77, NIGHT, 1);
			for (int x = 0; x < 639; x++) if ((rowA[x+1] == 8'hFE) != (rowB[x] == 8'hFE)) okStar = 0;
		end
		check(okStar, "stars : far offset + 1 -> 1 pixel left");
		f = 0; m = 0;
	end

	// skyline : the bottom row is all buildings ( building or window color )
	render(479, 0, 0, 0);
	check(count(0, 8'h6D) == 640, "day : bottom row is all buildings");

	// day : no stars , windows not lit ; night : stars and lit windows
	n = 0;
	for (int y = 0; y < 300; y += 1) begin
		if (y >= 40 && y < 170) continue;     // skip the cloud rows
		render(y, 0, 0, 0);
		n += count(0, 8'hFE);
	end
	check(n == 0, "day : no stars");
	n = 0;
	for (int y = 0; y < 300; y += 1) begin
		if (y >= 40 && y < 170) continue;     // skip the cloud rows
		render(y, 0, NIGHT, 0);
		n += count(0, 8'hFE);
	end
	check(n > 100 && n < 2000, $sformatf("night : %0d stars", n));
	render(420, 0, NIGHT, 0);
	check(count(0, 8'hF8) > 20, "night : lit windows");
	render(420, 0, 0, 0);
	check(count(0, 8'hF8) == 0 && count(0, 8'h92) > 20, "day : windows not lit");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
