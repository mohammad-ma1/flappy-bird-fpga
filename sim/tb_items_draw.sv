// self checking testbench for items_draw ( coins , the ghost shield , the hourglass and the purple trap )
// streams full frames and checks every pixel 2 clocks later against a reference model
`timescale 1ns/1ps

module tb_items_draw;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY;
logic signed [11:0] pipeX     [0:5];
logic        [8:0]  gapTop    [0:5];
logic        [8:0]  gapBottom [0:5];
logic               broken    [0:5];
logic        [1:0]  edgeCoin  [0:5];
logic               itemOn    [0:5];
logic        [1:0]  itemKind  [0:5];
logic signed [11:0] itemX     [0:5];
logic        [8:0]  itemY     [0:5];
int sq = 0;                       // the crushing pipes : every tube this many pixels closer to the middle
logic coinDrawingRequest, shieldItemDrawingRequest, hourglassDrawingRequest, confuseDrawingRequest;
logic [7:0] coinRGB, shieldItemRGB, hourglassRGB, confuseRGB;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

items_draw dut (.*);

int mX [0:5], mY [0:5], mItem [0:5], mSc [0:5], mScX [0:5], mScY [0:5];
int mGapH [0:5] = '{128, 128, 128, 128, 128, 128};
int mBroken [0:5] = '{0, 0, 0, 0, 0, 0};
int mShield [0:5] = '{0, 0, 0, 0, 0, 0};
int mGlass [0:5] = '{0, 0, 0, 0, 0, 0};
int mPurple [0:5] = '{0, 0, 0, 0, 0, 0};

task automatic set_items();      // the inputs of the DUT from the model ( m = model )
	for (int i = 0; i < 6; i++) begin
		pipeX[i]     = 12'(mX[i]);
		gapTop[i]    = 9'(mY[i] + sq);
		gapBottom[i] = 9'(mY[i] + mGapH[i] - sq);
		broken[i]    = (mBroken[i] != 0);
		edgeCoin[i]  = 2'(mItem[i]);
		itemOn[i]    = (mSc[i] != 0);
		itemKind[i]  = (mShield[i] != 0) ? 2'd1 : (mGlass[i] != 0) ? 2'd2 : (mPurple[i] != 0) ? 2'd3 : 2'd0;
		itemX[i]     = 12'(mX[i] - 24 - mScX[i]);
		itemY[i]     = 9'(mY[i] + mScY[i]);
	end
endtask

// the coin shape at ( ox , oy ) of a 16x16 box : {kind 1 , color}
function automatic logic [10:0] coin_pixel(input int ox, oy);
	int cx, cy, r2;
	cx = 2*ox - 15; cy = 2*oy - 15; r2 = cx*cx + cy*cy;
	if (r2 > 225) return 11'h0FF;
	if (r2 > 169) return {3'd1, 8'hA8};
	if (cx >= -3 && cx <= 3 && cy >= -9 && cy <= 9) return {3'd1, 8'hF0};
	return {3'd1, 8'hFC};
endfunction

// the shield shape : {kind 2 , color}
function automatic logic [10:0] shield_pixel(input int ox, oy);
	int cx, cy, r2;
	cx = 2*ox - 15; cy = 2*oy - 15; r2 = cx*cx + cy*cy;
	if (r2 > 225) return 11'h0FF;
	return {3'd2, (r2 > 169) ? 8'h1F : (r2 > 81) ? 8'hF8 : 8'hFE};
endfunction

// the hourglass : {kind 3 , color} - frame rows , glass triangles |x| <= |y| , sand ( reference , in pixels : dx = ox - 7.5 )
function automatic logic [10:0] glass_pixel(input int ox, oy);
	int cx, cy, ax, ay;
	cx = 2*ox - 15; cy = 2*oy - 15; ax = (cx < 0) ? -cx : cx; ay = (cy < 0) ? -cy : cy;
	if (ay >= 13) return (ax <= 11) ? {3'd3, 8'h8C} : 11'h0FF;
	if (ax > ay)  return 11'h0FF;
	if (ax + 2 > ay) return {3'd3, 8'hB6};
	if (cy > 0 && ay >= 5) return {3'd3, 8'hFC};
	if (ax <= 1) return {3'd3, 8'hFC};
	return {3'd3, 8'hDF};
endfunction

// the purple trap : {kind 4 , color}
function automatic logic [10:0] purple_pixel(input int ox, oy);
	int cx, cy, r2;
	cx = 2*ox - 15; cy = 2*oy - 15; r2 = cx*cx + cy*cy;
	if (r2 > 225) return 11'h0FF;
	return {3'd4, (r2 > 169) ? 8'h42 : (r2 > 25) ? 8'hA3 : 8'hE7};
endfunction

// reference model : returns {kind , color} , kind 0 none , 1 coin , 2 shield , 3 hourglass , 4 purple trap
// like the RTL loop : for every pipe the edge coin , then the scattered mItem - the last hit wins ( the shape is
// evaluated after the box is chosen , so a transparent corner still hides an earlier mItem )
function automatic logic [10:0] model(input int x, y);
	int top, bot, iy, ox, oy, hox, hoy, hkind;
	hkind = 0; hox = 0; hoy = 0;
	for (int i = 0; i < 6; i++) begin
		if ((mItem[i] == 1 || mItem[i] == 2) && mBroken[i] == 0) begin          // a shattered pipe has no edge coins
			top = mY[i] + sq;                                  // the edge coins move with the crushing tubes
			bot = mY[i] + mGapH[i] - sq;
			iy  = (mItem[i] == 1) ? top + 2 : bot - 18;
			ox = x - (mX[i] + 16); oy = y - iy;
			if (ox >= 0 && ox <= 15 && oy >= 0 && oy <= 15) begin hkind = 1; hox = ox; hoy = oy; end
		end
		if (mSc[i] != 0) begin
			ox = x - (mX[i] - 24 - mScX[i]); oy = y - (mY[i] + mScY[i]);
			if (ox >= 0 && ox <= 15 && oy >= 0 && oy <= 15) begin hkind = (mShield[i] != 0) ? 2 : (mGlass[i] != 0) ? 3 : (mPurple[i] != 0) ? 4 : 1; hox = ox; hoy = oy; end
		end
	end
	if (hkind == 4) return purple_pixel(hox, hoy);
	if (hkind == 3) return glass_pixel(hox, hoy);
	if (hkind == 2) return shield_pixel(hox, hoy);
	if (hkind == 1) return coin_pixel(hox, hoy);
	return 11'h0FF;
endfunction

logic [10:0] exp_q[$];
int coinPixels, shieldPixels, glassPixels, purplePixels;

task automatic compare(input string name);
	logic [10:0] e;
	logic [7:0] ec, es, eg, ep;
	e = exp_q.pop_front();
	ec = (e[10:8] == 1) ? e[7:0] : 8'hFF;
	es = (e[10:8] == 2) ? e[7:0] : 8'hFF;
	eg = (e[10:8] == 3) ? e[7:0] : 8'hFF;
	ep = (e[10:8] == 4) ? e[7:0] : 8'hFF;
	checks++;
	if (coinRGB !== ec || shieldItemRGB !== es || coinDrawingRequest !== (ec != 8'hFF) || shieldItemDrawingRequest !== (es != 8'hFF) ||
	    hourglassRGB !== eg || hourglassDrawingRequest !== (eg != 8'hFF) || confuseRGB !== ep || confuseDrawingRequest !== (ep != 8'hFF)) begin
		errors++;
		if (errors < 10) $display("FAIL %s : coin %h shield %h glass %h purple %h expected %h %h %h %h", name, coinRGB, shieldItemRGB, hourglassRGB, confuseRGB, ec, es, eg, ep);
	end
	if (coinDrawingRequest) coinPixels++;
	if (shieldItemDrawingRequest) shieldPixels++;
	if (hourglassDrawingRequest) glassPixels++;
	if (confuseDrawingRequest) purplePixels++;
endtask

task automatic scan_frame(input string name);
	coinPixels = 0; shieldPixels = 0; glassPixels = 0; purplePixels = 0;
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 640; x++) begin
			@(negedge clk);
			if (exp_q.size() == 2) compare(name);
			pixelX = 11'(x); pixelY = 11'(y);
			exp_q.push_back(model(x, y));
		end
	repeat (2) begin @(negedge clk); compare(name); end
	$display("%s : %0d coin , %0d shield , %0d hourglass , %0d purple pixels", name, coinPixels, shieldPixels, glassPixels, purplePixels);
endtask

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

initial begin
	pixelX = 0; pixelY = 0;
	mX = '{100, 300, 500, -20, 1500, 1700};
	mY = '{50, 200, 300, 150, 100, 100};
	mItem  = '{1, 2, 3, 1, 0, 0};                 // mItem code 3 is not used : nothing is drawn for it
	mSc    = '{0, 1, 1, 0, 1, 0};
	mScX   = '{0, 10, 63, 0, 30, 0};
	mScY   = '{0, 8, 103, 0, 40, 0};
	set_items();
	resetN = 1'b0;
	#22;
	check(!coinDrawingRequest && !shieldItemDrawingRequest, "nothing drawn during reset");
	resetN = 1'b1;

	// coin at the top of pipe 0 , coin at the bottom of pipe 1 , unused code 3 in pipe 2 , a coin partly off-screen ( pipe 3 at X -20 )
	scan_frame("coins");
	check(coinPixels > 3 * 150 && shieldPixels == 0, "coins : edge and scattered coins ( some partly off-screen ) , round , about 180 pixels each");

	// the scattered coin moves with its pipe : pipe 1 is 100 pixels lower
	mY[1] = 300;
	set_items();
	scan_frame("pipe 1 moved down , its coins move too");

	// random gap heights : the bottom coin of pipe 1 follows its gap ( 112 ) , pipe 0 shattered : no edge coin ,
	// the scattered mItem of pipe 1 is a ghost shield
	mGapH     = '{128, 112, 143, 128, 128, 128};
	mBroken   = '{1, 0, 0, 0, 0, 0};
	mShield = '{0, 1, 0, 0, 0, 0};
	set_items();
	scan_frame("random gaps , shattered pipe , shield mItem");
	check(shieldPixels > 150, "shield mItem drawn ( round )");
	mBroken   = '{0, 0, 0, 0, 0, 0};
	mShield = '{0, 0, 0, 0, 0, 0};

	// the rare items : an hourglass ( pipe 2 ) and a purple trap ( pipe 1 )
	mGlass  = '{0, 0, 1, 0, 0, 0};
	mPurple = '{0, 1, 0, 0, 0, 0};
	set_items();
	scan_frame("hourglass and purple trap");
	check(glassPixels > 100 && purplePixels > 150, "the hourglass and the purple trap are drawn");
	mGlass  = '{0, 0, 0, 0, 0, 0};
	mPurple = '{0, 0, 0, 0, 0, 0};

	// the crushing pipes : the edge coins move 30 pixels inside with the tubes
	sq = 30;
	set_items();
	scan_frame("crushing pipes , the edge coins move");
	sq = 0;

	// no items
	mItem = '{0, 0, 0, 0, 0, 0};
	mSc   = '{0, 0, 0, 0, 0, 0};
	set_items();
	scan_frame("no items");
	check(coinPixels == 0 && shieldPixels == 0, "no items : nothing drawn");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
