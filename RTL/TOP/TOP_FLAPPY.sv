// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// TOP_FLAPPY : the board top level ( DE10-Standard )
//   CLK_31P5 PLL ( 50 MHz -> 31.5 MHz ) , VGA_Controller , TOP_KBD ( PS2 keyboard ) , AUDIO ( melodies ) ,
//   SEG7 7-segment decoders - all from Lab1Demo , unchanged - and flappy_game_core ( the game )
// the port names are the names of Lab1Demo constraints/pin.tcl
//
// controls :  ENTER                      start / restart
//             numpad 8 / KEY[2]          move the maze up
//             numpad 2 / KEY[1]          move the maze down
//             KEY[2] + KEY[1] together   start / restart ( without a keyboard )
//             KEY[3]                     volume ( as in Lab1Demo )
//             KEY[0]                     reset
//             SW[0] cheat no-death , SW[1] turbo , SW[4] up : HEX3..HEX0 show the BEST score
// displays :  HEX3..HEX0 score ( or best score with SW[4] ) , HEX4 level 1..8 ( HEX5 dark ) ,
//             LEDR[2:0] level , LEDR[3] cheat , LEDR[4] turbo , LEDR[5] keys swapped ( purple trap ) , LEDR[6] slow motion ( hourglass ) ,
//             LEDR[8:7] game state , LEDR[9] ghost shield

module	TOP_FLAPPY	(
					input	logic	CLOCK_50,
					input	logic	resetN_pin,      // KEY[0]
					input	logic	[3:1] KEY,       // push buttons , active low
					input	logic	[9:0] SW,
					input	logic	PS2_CLK,
					input	logic	PS2_DAT,
					input	logic	[1:2] AUDIN,     // the same bus order as Lab1Demo ( AUDIN[1..2] )
					output	logic	[4:7] AUDOUT,    // AUDOUT[4..7]
					output	logic	[28:0] OVGA,
					output	logic	[6:0] HEX0,
					output	logic	[6:0] HEX1,
					output	logic	[6:0] HEX2,
					output	logic	[6:0] HEX3,
					output	logic	[6:0] HEX4,
					output	logic	[6:0] HEX5,
					output	logic	[9:0] LEDR
);

logic        clk ;            // 31.5 MHz
logic        resetN ;
logic signed [10:0] pixelX , pixelY ;
logic        startOfFrame ;
logic [7:0]  RGB ;

logic [9:0]  keyIsPressed ;   // numpad digits , high while pressed
logic        enterKey ;
logic [3:1]  KEY_meta , KEY_sync ;   // push buttons and switches are synchronized to clk ( 2 flip-flops )
logic [2:0]  SW_meta , SW_sync ;   // SW[0] , SW[1] , SW[4]
logic [15:0] hexScore ;       // the number on HEX3..HEX0

logic        startKey , keyUp , keyDown ;
logic [1:0]  gameState ;
logic [15:0] scoreBCD , highScoreBCD ;
logic [2:0]  level ;
logic        shieldActive , slowMoActive , invertControls ;
logic [3:0]  melodySelect ;
logic        startMelody ;

assign resetN = resetN_pin ;

//////////--------------------------------------------------------------------------------------------------------------=
// clock , VGA , keyboard ( Lab1Demo blocks )
CLK_31P5 pll_inst (
	.refclk(CLOCK_50), .rst(!resetN_pin), .outclk_0(clk), .locked() );   // the reset button also re-locks the PLL

VGA_Controller vga_inst (
	.RGBIn(RGB), .PixelX(pixelX), .PixelY(pixelY), .startOfFrame(startOfFrame),
	.oVGA(OVGA), .address(), .clk(clk), .resetN(resetN) );

TOP_KBD keyboard_inst (
	.resetN(resetN), .PS2_CLK(PS2_CLK), .PS2_DAT(PS2_DAT), .CLOCK_50(clk),
	.keyPadValid(), .Plus(), .back(), .slash(), .del(), .enter(enterKey), .minus(), .star(), .num(),
	.keyPad(), .keyIsPressed(keyIsPressed) );

//////////--------------------------------------------------------------------------------------------------------------=
// buttons and switches : 2 flip-flop synchronizers
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		KEY_meta <= 3'b111 ;  KEY_sync <= 3'b111 ;
		SW_meta  <= 3'b000 ;   SW_sync  <= 3'b000 ;
	end
	else begin
		KEY_meta <= KEY ;        KEY_sync <= KEY_meta ;
		SW_meta  <= {SW[4], SW[1:0]} ;  SW_sync <= SW_meta ;
	end
end

assign keyUp    = keyIsPressed[8] || !KEY_sync[2] ;
assign keyDown  = keyIsPressed[2] || !KEY_sync[1] ;
assign startKey = enterKey || (!KEY_sync[2] && !KEY_sync[1]) ;

//////////--------------------------------------------------------------------------------------------------------------=
// the game
flappy_game_core game_inst (
	.clk(clk), .resetN(resetN),
	.pixelX(pixelX), .pixelY(pixelY), .startOfFrame(startOfFrame),
	.startKey(startKey), .keyUp(keyUp), .keyDown(keyDown),
	.cheatNoDeath(SW_sync[0]), .turbo(SW_sync[1]),
	.RGBOut(RGB), .gameState(gameState), .scoreBCD(scoreBCD), .highScoreBCD(highScoreBCD), .level(level),
	.shieldActive(shieldActive), .slowMoActive(slowMoActive), .invertControls(invertControls),
	.melodySelect(melodySelect), .startMelody(startMelody) );

//////////--------------------------------------------------------------------------------------------------------------=
// sound ( Lab1Demo AUDIO block : plays the melody keyPad when keypadValid )
AUDIO audio_inst (
	.resetN(resetN), .clk(clk), .volume(KEY[3]),
	.keypadValid(startMelody), .keyPad(melodySelect),
	.AUDIN(AUDIN), .AUDOUT(AUDOUT) );

//////////--------------------------------------------------------------------------------------------------------------=
// 7-segment : score ( SW[4] : best score ) on HEX3..HEX0 , level on HEX4 ( HEX5 dark )
assign hexScore = SW_sync[2] ? highScoreBCD : scoreBCD ;   // SW_sync[2] = SW[4]
SEG7 hex0_inst (.clk(clk), .resetN(resetN), .iDIG(hexScore[3:0]),   .darkN(1'b1), .oSEG(HEX0));
SEG7 hex1_inst (.clk(clk), .resetN(resetN), .iDIG(hexScore[7:4]),   .darkN(1'b1), .oSEG(HEX1));
SEG7 hex2_inst (.clk(clk), .resetN(resetN), .iDIG(hexScore[11:8]),  .darkN(1'b1), .oSEG(HEX2));
SEG7 hex3_inst (.clk(clk), .resetN(resetN), .iDIG(hexScore[15:12]), .darkN(1'b1), .oSEG(HEX3));
SEG7 hex4_inst (.clk(clk), .resetN(resetN), .iDIG({1'b0, level} + 4'd1), .darkN(1'b1), .oSEG(HEX4));   // level shown as 1 .. 8
SEG7 hex5_inst (.clk(clk), .resetN(resetN), .iDIG(4'd0), .darkN(1'b0),  .oSEG(HEX5));   // not used : dark

// LEDs
assign LEDR[2:0] = level ;
assign LEDR[3]   = SW_sync[0] ;
assign LEDR[4]   = SW_sync[1] ;
assign LEDR[5]   = invertControls ;   // purple trap : the keys are swapped
assign LEDR[6]   = slowMoActive ;     // hourglass : slow motion
assign LEDR[8:7] = gameState ;
assign LEDR[9]   = shieldActive ;     // ghost shield

endmodule
