// self checking testbench for flappy_objects_mux
// 1. every combination of state x 10 drawing requests against a reference model ( priority , game over dimming )
// 2. the shield ring around the bird
// 3. the spotlight : inside the circle normal , the ring dimmed , outside black , text always visible
`timescale 1ns/1ps

module tb_flappy_objects_mux;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY, spotCenterX, spotCenterY;
logic [1:0] gameState;
logic spotlightOn, shieldActive;
logic shieldItemDR, hourglassDR, confuseDR, sunDR, pipesVisible;
logic hudDR, overlayDR, birdDR, coinDR, pipesDR;
logic [7:0] RGBOut;

localparam logic [7:0] TEXT_C    = 8'hE3 ;
localparam logic [7:0] BIRD_C    = 8'hFC ;
localparam logic [7:0] COIN_C    = 8'hF0 ;
localparam logic [7:0] PIPES_C   = 8'h1C ;
localparam logic [7:0] BG_C      = 8'h97 ;
localparam logic [7:0] SHIELD_IT_C = 8'hF8 ;
localparam logic [7:0] GLASS_C   = 8'h8C ;
localparam logic [7:0] PURPLE_C  = 8'hA3 ;
localparam logic [7:0] SUN_C     = 8'hFC ;
localparam logic [7:0] RING_C    = 8'h1F ;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_objects_mux dut (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .gameState(gameState),
	.spotlightOn(spotlightOn), .spotCenterX(spotCenterX), .spotCenterY(spotCenterY),
	.shieldItemDrawingRequest(shieldItemDR), .shieldItemRGB(SHIELD_IT_C),
	.shieldActive(shieldActive), .hourglassDrawingRequest(hourglassDR), .hourglassRGB(GLASS_C),
	.confuseDrawingRequest(confuseDR), .confuseRGB(PURPLE_C),
	.textRGB(TEXT_C), .hudDrawingRequest(hudDR), .overlayDrawingRequest(overlayDR),
	.birdDrawingRequest(birdDR), .birdRGB(BIRD_C), .coinDrawingRequest(coinDR), .coinRGB(COIN_C),

	.pipesDrawingRequest(pipesDR), .pipesRGB(PIPES_C), .pipesVisible(pipesVisible),
	.celestialDrawingRequest(sunDR), .celestialRGB(SUN_C), .backGroundRGB(BG_C),
	.RGBOut(RGBOut) );

function automatic logic [7:0] dim(input logic [7:0] c);
	return {1'b0, c[7:6], 1'b0, c[4:3], 1'b0, c[1]};
endfunction

// reference model ( spotlight off )
function automatic logic [7:0] model(input logic [1:0] st, input logic [9:0] dr);   // {pipesVisible, hud, overlay, bird, shieldItem, hourglass, purple, coin, pipes, sun}
	logic [7:0] scene;
	if (st != 2'd1 && dr[7]) return TEXT_C;               // the overlay only outside PLAY
	if (dr[8])               return TEXT_C;               // the HUD always
	scene = dr[6] ? BIRD_C : dr[5] ? SHIELD_IT_C : dr[4] ? GLASS_C : dr[3] ? PURPLE_C :
	        dr[2] ? COIN_C : (dr[1] && dr[9]) ? PIPES_C : dr[0] ? SUN_C : BG_C;   // invisible pipes show what is behind
	if (st == 2'd2) return dim(scene);
	return scene;
endfunction

task automatic check(input logic [7:0] exp, input string what);
	checks++;
	if (RGBOut !== exp) begin
		errors++;
		if (errors < 15) $display("FAIL %s : got %h expected %h", what, RGBOut, exp);
	end
endtask

// a pixel with constant inputs : wait for the 2 clocks pixel delay + 1 clock register
task automatic hold_pixel(input int x, y);
	@(negedge clk);
	pixelX = 11'(x); pixelY = 11'(y);
	repeat (3) @(negedge clk);
endtask

int dist2;

initial begin
	gameState = 2'd0; spotlightOn = 1'b0; shieldActive = 1'b0; spotCenterX = 11'sd176; spotCenterY = 11'sd240;
	pixelX = 0; pixelY = 0;
	{pipesVisible, hudDR, overlayDR, birdDR, shieldItemDR, hourglassDR, confuseDR, coinDR, pipesDR, sunDR} = '1;
	resetN = 1'b0;
	#23;
	check(8'h00, "output is 0 during reset");
	@(negedge clk) resetN = 1'b1;

	// 1. priority : 4 states x 1024 drawing request combinations ( registered : one clock later )
	//    UI > bird > shield item > hourglass > purple trap > coin > pipes ( only while visible ) > sun / moon > background
	for (int s = 0; s < 4; s++)
		for (int k = 0; k < 1024; k++) begin
			@(negedge clk);
			gameState = s[1:0];
			{pipesVisible, hudDR, overlayDR, birdDR, shieldItemDR, hourglassDR, confuseDR, coinDR, pipesDR, sunDR} = k[9:0];
			@(negedge clk);
			check(model(s[1:0], k[9:0]), $sformatf("state %0d requests %b", s, k[9:0]));
		end

	// 2. the shield ring : 18..22 pixels from the bird center ( 176 , 240 ) , under the bird
	gameState = 2'd1;
	{pipesVisible, hudDR, overlayDR, birdDR, shieldItemDR, hourglassDR, confuseDR, coinDR, pipesDR, sunDR} = 10'b1000000010;
	hold_pixel(176 + 20, 240); check(PIPES_C, "no shield : no ring");
	shieldActive = 1'b1;
	hold_pixel(176 + 20, 240); check(RING_C,  "shield : the ring at 20 pixels");
	hold_pixel(176, 240 - 18); check(RING_C,  "shield : the ring at 18 pixels ( above )");
	hold_pixel(176 - 22, 240); check(RING_C,  "shield : the ring at 22 pixels ( left )");
	hold_pixel(176 + 17, 240); check(PIPES_C, "17 pixels : inside the ring");
	hold_pixel(176 + 23, 240); check(PIPES_C, "23 pixels : outside the ring");
	birdDR = 1'b1;    hold_pixel(176 + 20, 240); check(BIRD_C,    "the bird is in front of the ring");
	birdDR = 1'b0;    shieldItemDR = 1'b1; hold_pixel(176 + 20, 240); check(RING_C, "the ring is in front of the items");
	shieldItemDR = 1'b0; shieldActive = 1'b0;

	// 3. night mode ( PLAY ) : the center is 100 pixels right of the bird ( 176 + 100 = 276 , 240 ) ,
	//    dist^2 < 19600 ( 140 ) normal , up to 25600 ( 160 ) half brightness
	gameState = 2'd1; spotlightOn = 1'b1;
	{pipesVisible, hudDR, overlayDR, birdDR, shieldItemDR, hourglassDR, confuseDR, coinDR, pipesDR, sunDR} = 10'b1000000010;   // pipes everywhere
	hold_pixel(276, 240);       check(PIPES_C,      "spotlight center ( 100 pixels right of the bird ) : normal");
	hold_pixel(176, 240);       check(PIPES_C,      "the bird is inside the light");
	hold_pixel(276 + 139, 240); check(PIPES_C,      "inside the radius ( 139 , 19321 < 19600 ) : normal");
	hold_pixel(276 + 140, 240); check(dim(PIPES_C), "140 ( 19600 is not < 19600 ) : the glowing ring");
	hold_pixel(276 + 98, 240 + 98); check(PIPES_C, "inside on a diagonal ( 98,98 = 19208 ) : normal");
	hold_pixel(276 + 99, 240 + 99); check(dim(PIPES_C), "the ring on a diagonal ( 99,99 = 19602 ) : half brightness");
	hold_pixel(276 + 159, 240); check(dim(PIPES_C), "159 ( 25281 < 25600 ) : still the glowing ring");
	hold_pixel(276 + 161, 240); check(8'h00,        "outside ( 161 , 25921 > 25600 ) : black");
	hold_pixel(0, 240);         check(8'h00,        "far behind the bird ( X 0 : 276^2 = 76176 ) : black");
	hold_pixel(600, 50);      check(8'h00,      "far away : black");
	hudDR = 1'b1;
	hold_pixel(600, 50);      check(TEXT_C,      "the text is visible in the dark");
	hudDR = 1'b0;

	// a full row through the center : count the normal , dimmed and black pixels
	begin
		int normal, dimmed, dark;
		normal = 0; dimmed = 0; dark = 0;
		for (int x = 0; x < 640; x++) begin
			hold_pixel(x, 240);
			if (RGBOut == PIPES_C) normal++; else if (RGBOut == dim(PIPES_C)) dimmed++; else if (RGBOut == 8'h00) dark++;
		end
		$display("     row 240 : %0d normal , %0d dimmed , %0d black", normal, dimmed, dark);
		checks++;
		if (normal != 279 || dimmed != 42 || dark != 319) begin errors++; $display("FAIL night mode row counts"); end   // normal 137..415 , dim 116..136 + 416..436 , black the rest
	end

	// spotlight only in PLAY , and only when on
	gameState = 2'd0; hold_pixel(600, 50); check(PIPES_C, "START : no spotlight");
	gameState = 2'd1; spotlightOn = 1'b0; hold_pixel(600, 50); check(PIPES_C, "spotlight off : normal");

	// asynchronous reset
	#2 resetN = 1'b0;
	#1 check(8'h00, "async reset clears the output");
	resetN = 1'b1;

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
