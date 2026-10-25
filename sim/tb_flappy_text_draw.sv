// self checking testbench for flappy_text_draw
// renders full frames ( one pixel per clock , output taken 2 clocks later ) for every game state
`timescale 1ns/1ps

module tb_flappy_text_draw;

logic clk = 1'b0;
logic resetN;
logic startOfFrame = 1'b0;
logic signed [10:0] pixelX, pixelY;
logic [1:0]  gameState;
logic [15:0] scoreBCD, highScoreBCD;
logic [2:0]  level;
logic        invertControls;
logic [3:0]  msgId = 4'd0;
logic hudDrawingRequest, overlayDrawingRequest;
logic [7:0] textRGB;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_text_draw dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

// one rendered frame
logic [7:0] rgb [0:479][0:639];
logic       hud [0:479][0:639];
logic       ovl [0:479][0:639];
int hudCount, ovlCount;

task automatic render(input logic [1:0] st);
	int px, py;
	gameState = st;
	hudCount = 0; ovlCount = 0;
	for (int i = 0; i < 640*480 + 2; i++) begin
		@(negedge clk);
		if (i >= 2) begin
			px = (i-2) % 640; py = (i-2) / 640;
			hud[py][px] = hudDrawingRequest;
			ovl[py][px] = overlayDrawingRequest;
			rgb[py][px] = (hudDrawingRequest || overlayDrawingRequest) ? textRGB : 8'hFF;
			if (hudDrawingRequest) hudCount++;
			if (overlayDrawingRequest) ovlCount++;
			if (hudDrawingRequest && overlayDrawingRequest) begin errors++; $display("FAIL hud and overlay together"); end
		end
		pixelX = 11'(i < 640*480 ? i % 640 : 0);
		pixelY = 11'(i < 640*480 ? i / 640 : 0);
	end
endtask

// independent copy of a few glyphs ( bit 4 = left pixel )
function automatic logic [4:0] glyph_row(input byte ch, input int r);
	logic [0:6][4:0] g;
	case (ch)
		"S": g = {5'b01111, 5'b10000, 5'b10000, 5'b01110, 5'b00001, 5'b00001, 5'b11110};
		"1": g = {5'b00100, 5'b01100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110};
		"2": g = {5'b01110, 5'b10001, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b11111};
		"3": g = {5'b11111, 5'b00010, 5'b00100, 5'b00010, 5'b00001, 5'b10001, 5'b01110};
		default: g = {5'b00010, 5'b00110, 5'b01010, 5'b10010, 5'b11111, 5'b00010, 5'b00010}; // "4"
	endcase
	if (r < 0 || r > 6) return 5'b0;
	return g[r];
endfunction

// check one character cell of a x2 line : glyph pixels in the color , shadow pixels black
int badGlyph;
task automatic check_char(input int x0, input int y0, input byte ch, input logic [7:0] color);
	logic [4:0] row, above;
	logic on, sh;
	for (int r = 0; r < 8; r++)
		for (int c = 0; c < 8; c++) begin
			row   = glyph_row(ch, r);       // row 7 and row -1 are empty
			above = glyph_row(ch, r - 1);
			on = (c < 5) && row[4 - c];
			sh = !on && (c >= 1) && (c <= 5) && above[5 - c];
			for (int dy = 0; dy < 2; dy++)
				for (int dx = 0; dx < 2; dx++)
					if (rgb[y0 + 2*r + dy][x0 + 2*c + dx] != (on ? color : sh ? 8'h00 : 8'hFF)) badGlyph++;
		end
endtask

int diff, outside;

// n frame pulses ( for the blinking / rainbow counters )
task automatic frames(input int n);
	repeat (n) begin
		@(negedge clk) startOfFrame = 1'b1;
		@(negedge clk) startOfFrame = 1'b0;
	end
endtask

// count the drawn pixels of one color ( or any drawn color when col = FF ) in a box
function automatic int count_box(input int x0, x1, y0, y1, input logic [7:0] col);
	int n = 0;
	for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++)
		if (rgb[y][x] != 8'hFF && (col == 8'hFF || rgb[y][x] == col)) n++;
	return n;
endfunction

logic [7:0] RAINBOW_M [0:7] = '{8'hE0, 8'hF4, 8'hFC, 8'h9C, 8'h1C, 8'h1F, 8'h9F, 8'hE3};
int nA, nB, c0, c1;
logic prevDrawn [0:479][0:639];   // drawn pixels of the previous frame

initial begin
	pixelX = 0; pixelY = 0; gameState = 0; level = 3'd2; invertControls = 1'b0;
	scoreBCD = 16'h0000; highScoreBCD = 16'h0042;
	resetN = 1'b0;
	#22 resetN = 1'b1;

	// START : overlay only
	render(2'd0);
	$display("START : %0d overlay pixels", ovlCount);
	check(ovlCount > 2000 && hudCount == 0, "START : overlay text , no HUD");

	// READY! ( x4 , 6 cells of 32 at x 224 , y 96 ) : rainbow color 0 after reset , the next color after 8 frames
	c0 = count_box(224, 416, 96, 128, RAINBOW_M[0]);
	nA = count_box(224, 416, 96, 128, 8'hFF);
	// the '!' is the 6th cell : x 384..415 , its stem is font column 2 = x 392..395 ( 4 px ) , font rows 0..4 = 20 px
	c1 = count_box(392, 400, 96, 116, RAINBOW_M[0]);
	check(c0 > 500 && c1 == 4*20, $sformatf("READY! in rainbow color 0 , with the '!' ( %0d , %0d )", c0, c1));
	nB = count_box(160, 480, 232, 248, 8'hFE);
	check(nB > 800, $sformatf("PRESS ENTER TO START is shown ( 20 characters x2 ) : %0d", nB));
	check(count_box(448, 480, 232, 248, 8'hFE) > 20, "PRESS ENTER TO START : the last 'T' at x 464..479");
	frames(8);
	render(2'd0);
	check(count_box(224, 416, 96, 128, RAINBOW_M[1]) == c0 && count_box(224, 416, 96, 128, RAINBOW_M[0]) == 0,
	      "8 frames later READY! has the next rainbow color");
	frames(8*7);   // 64 frames from reset : the rainbow wrapped back to color 0 , the blink is off ( 36..71 )
	render(2'd0);
	check(count_box(224, 416, 96, 128, RAINBOW_M[0]) == c0, "the rainbow cycles through 8 colors");
	check(count_box(160, 480, 232, 248, 8'hFF) == 0, "PRESS ENTER TO START blinks off after 36 frames");
	check(count_box(208, 432, 272, 288, 8'h1F) > 200, "8 UP 2 DOWN does not blink");
	frames(8);     // 72 frames : the blink is on again
	render(2'd0);
	check(count_box(160, 480, 232, 248, 8'hFE) == nB, "PRESS ENTER TO START is back after another 36 frames");

	// PLAY : HUD only , in the top band ( y 12..27 )
	scoreBCD = 16'h1234;
	render(2'd1);
	$display("PLAY : %0d HUD pixels", hudCount);
	check(hudCount > 300 && ovlCount == 0, "PLAY : HUD text , no overlay");
	outside = 0;
	for (int y = 0; y < 480; y++) for (int x = 0; x < 640; x++) if (hud[y][x] && (y < 12 || y >= 28)) outside++;
	check(outside == 0, "PLAY : the HUD stays in the top band");

	// the digits of "SCORE 1234" : line at (12,12) , x2 font ( 16 pixel cells ) , digits are characters 6..9
	badGlyph = 0;
	check_char(12 + 0*16, 12, "S", 8'hFE);
	check_char(12 + 6*16, 12, "1", 8'hFE);
	check_char(12 + 7*16, 12, "2", 8'hFE);
	check_char(12 + 8*16, 12, "3", 8'hFE);
	check_char(12 + 9*16, 12, "4", 8'hFE);
	check(badGlyph == 0, $sformatf("glyphs 'S' '1' '2' '3' '4' and their shadows pixel exact (%0d bad)", badGlyph));

	// changing the score changes only the digit cells
	for (int y = 0; y < 480; y++) for (int x = 0; x < 640; x++) prevDrawn[y][x] = (rgb[y][x] != 8'hFF);
	scoreBCD = 16'h0000;
	render(2'd1);
	diff = 0; outside = 0;
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 640; x++)
			if (prevDrawn[y][x] != hudDrawingRequest_at(y, x)) begin
				diff++;
				if (!(y >= 12 && y < 28 && x >= 12 + 6*16 && x < 12 + 10*16)) outside++;
			end
	check(diff > 0 && outside == 0, "score 1234 -> 0000 changes only the 4 digit cells");

	// no TIME line any more : nothing is drawn in the band y 36..51
	outside = 0;
	for (int y = 36; y < 52; y++) for (int x = 0; x < 640; x++) if (hud[y][x]) outside++;
	check(outside == 0, "no TIME line ( the time challenge was removed )");

	// REVERSED : only while the controls are inverted ( red , at X 256..383 , Y 12..27 )
	invertControls = 1'b1;
	render(2'd1);
	diff = 0;
	for (int y = 12; y < 28; y++) for (int x = 256; x < 384; x++) if (hud[y][x] && rgb[y][x] == 8'hE0) diff++;
	check(diff > 100, "REVERSED is shown in red while the controls are inverted");
	invertControls = 1'b0;
	render(2'd1);
	diff = 0;
	for (int y = 12; y < 28; y++) for (int x = 256; x < 384; x++) if (hud[y][x]) diff++;
	check(diff == 0, "no REVERSED when the controls are normal");

	// EVENT MESSAGES ( PLAY ) : title x4 at y 60..91 , subtitle x2 at y 100..115 , centered
	msgId = 4'd4;                                   // CLOSING PIPES! - LEVEL @
	render(2'd1);
	nA = count_box(0, 640, 60, 92, 8'hE0);
	nB = count_box(0, 640, 100, 116, 8'hFE);
	$display("     CLOSING PIPES! : %0d red title pixels , %0d white subtitle pixels", nA, nB);
	check(nA > 1500 && nB > 200, "message : CLOSING PIPES! title in red and LEVEL n under it");
	check(count_box(0, 640, 60, 92, 8'hFF) == nA + count_box(0, 640, 60, 92, 8'h00), "message : the title has only its color and the shadow");
	check(count_box(0, 96, 60, 116, 8'hFF) == 0 && count_box(544, 640, 60, 116, 8'hFF) == 0, "message : centered ( nothing near the edges )");
	check(hudCount > 1500 + 300 && ovlCount == 0, "message : drawn as HUD ( PLAY ) text");
	msgId = 4'd7;                                   // SHIELD! - 10 SECONDS
	render(2'd1);
	check(count_box(0, 640, 60, 92, 8'h1F) > 500 && count_box(0, 640, 60, 92, 8'hE0) == 0, "message : SHIELD! in cyan replaces it");
	render(2'd0);
	check(count_box(0, 640, 60, 92, 8'h1F) == 0, "message : not on the START screen");
	msgId = 4'd0;
	render(2'd1);
	check(count_box(0, 640, 56, 120, 8'hFF) == 0, "message : msgId 0 -> no message");
	// GAME_OVER : overlay only
	render(2'd2);
	$display("GAME_OVER : %0d overlay pixels", ovlCount);
	check(ovlCount > 2000 && hudCount == 0, "GAME_OVER : overlay text , no HUD");
	check(count_box(176, 464, 96, 128, 8'hE0) > 500 && count_box(176, 464, 96, 128, 8'hFF) == count_box(176, 464, 96, 128, 8'hE0) + count_box(176, 464, 96, 128, 8'h00),
	      "GAME OVER in bright red ( with a black shadow )");
	nB = count_box(144, 496, 312, 328, 8'hFE);
	check(nB > 900, $sformatf("PRESS ENTER TO RESTART is shown ( 22 characters ) : %0d", nB));
	frames(36);
	render(2'd2);
	check(count_box(144, 496, 312, 328, 8'hFF) == 0 && count_box(176, 464, 96, 128, 8'hE0) > 500,
	      "PRESS ENTER TO RESTART blinks , GAME OVER stays");

	// state 3 is not used : nothing
	render(2'd3);
	check(ovlCount == 0 && hudCount == 0, "state 3 : no text");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

function automatic logic hudDrawingRequest_at(input int y, input int x);
	return rgb[y][x] != 8'hFF;
endfunction

endmodule
