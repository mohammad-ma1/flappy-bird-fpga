// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_text_draw : all the text on the screen , from a small 5x7 pixel font
//
//   START     : "READY!" ( big , rainbow colors ) , "PRESS ENTER TO START" ( blinking ) , the keys , the best score
//   PLAY      : the HUD - "SCORE 0012" , "LEVEL 2" , "REVERSED" ( only while the keys are swapped )
//               and the event message of the game controller ( 2 seconds ) : a big title and a small line under it
//   GAME_OVER : "GAME OVER" ( big , red ) , the score , the best score , "PRESS ENTER TO RESTART" ( blinking )
//
//   how a letter is drawn : the screen is cut into character CELLS . a cell is 8x8 font pixels ( a 5x7 letter + space ) .
//     small text : every font pixel is 2x2 screen pixels , a cell is 16x16
//     big text   : every font pixel is 4x4 screen pixels , a cell is 32x32
//   so for a pixel inside a text line : character number = x / cell size , font column = ( x / font pixel ) % 8
//   ( divisions by 2 , 4 , 16 , 32 are only wires in hardware - the low bits are dropped )
//   every letter has a black shadow one font pixel down-right , so the text can be read on any background
//   two registered stages = 2 clocks latency , like every drawing module

module	flappy_text_draw	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	startOfFrame,               // for the blinking and the rainbow
	input	logic	signed [10:0] pixelX,       // the current VGA pixel
	input	logic	signed [10:0] pixelY,
	input	logic	[1:0]  gameState,           // 0 START , 1 PLAY , 2 GAME_OVER
	input	logic	[15:0] scoreBCD,            // the numbers on the screen
	input	logic	[15:0] highScoreBCD,
	input	logic	[2:0]  level,
	input	logic	invertControls,             // show REVERSED
	input	logic	[3:0]  msgId,               // the event message ( 0 = none )

	output	logic	[7:0] textRGB,              // the text color
	output	logic	hudDrawingRequest,          // text of PLAY ( the HUD and the messages )
	output	logic	overlayDrawingRequest       // text of START / GAME_OVER
);

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;
localparam logic [7:0] SHADOW_COLOR   = 8'h00 ;    // black
localparam logic [1:0] STATE_PLAY     = 2'd1 ;
localparam logic [5:0] SPACE_CODE     = 6'd36 ;    // the character codes : 0-9 , A-Z = 10..35 , space 36 , ! 37 ,
localparam logic [5:0] LAST_CODE      = 6'd37 ;    // and 48..56 = a digit of a number ( see below )
localparam int MSG_TITLE_Y    = 60 ;               // the message title : big text , below the HUD
localparam int MSG_SUB_Y      = 100 ;              // the line under it  : small text
localparam logic [1:0] FX_BLINK   = 2'd1 ;         // text effects of a line : 0 steady , 1 blinking , 2 rainbow
localparam logic [1:0] FX_RAINBOW = 2'd2 ;
localparam logic [5:0] BLINK_FRAMES   = 6'd36 ;    // blinking : half a second on , half a second off

// the rainbow colors : red , orange , yellow , lime , green , cyan , sky , magenta
function automatic logic [7:0] rainbowColor (input logic [2:0] k);
	case (k)
		3'd0:    return 8'hE0 ;
		3'd1:    return 8'hF4 ;
		3'd2:    return 8'hFC ;
		3'd3:    return 8'h9C ;
		3'd4:    return 8'h1C ;
		3'd5:    return 8'h1F ;
		3'd6:    return 8'h9F ;
		default: return 8'hE3 ;
	endcase
endfunction

// the tables ( made by tools\gen_text_tables.ps1 ) :
//   FONT      : 7 rows of 5 bits for every character ( bit 4 = the left pixel )
//   LINE_*    : 4 text lines for every game state , line number = 4 x gameState + k :
//               Y , X , SHIFT ( 1 small , 2 big ) , LEN ( characters ) , COLOR , FX ( effect ) , TEXT ( character codes )
//   MSG_*     : 2 lines for every message , entry = 2 x msgId ( the title ) and 2 x msgId + 1 ( the line under it )
// ---- generated tables ( tools\gen_text_tables.ps1 ) - do not edit by hand ----
// 5x7 font : 38 characters ( 0-9 , A-Z , space , ! ) , 7 rows of 5 pixels , bit 4 = left pixel
logic [0:37][0:6][4:0] FONT = {
	5'b01110, 5'b10001, 5'b10011, 5'b10101, 5'b11001, 5'b10001, 5'b01110,   // '0'
	5'b00100, 5'b01100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110,   // '1'
	5'b01110, 5'b10001, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b11111,   // '2'
	5'b11111, 5'b00010, 5'b00100, 5'b00010, 5'b00001, 5'b10001, 5'b01110,   // '3'
	5'b00010, 5'b00110, 5'b01010, 5'b10010, 5'b11111, 5'b00010, 5'b00010,   // '4'
	5'b11111, 5'b10000, 5'b11110, 5'b00001, 5'b00001, 5'b10001, 5'b01110,   // '5'
	5'b00110, 5'b01000, 5'b10000, 5'b11110, 5'b10001, 5'b10001, 5'b01110,   // '6'
	5'b11111, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b01000, 5'b01000,   // '7'
	5'b01110, 5'b10001, 5'b10001, 5'b01110, 5'b10001, 5'b10001, 5'b01110,   // '8'
	5'b01110, 5'b10001, 5'b10001, 5'b01111, 5'b00001, 5'b00010, 5'b01100,   // '9'
	5'b01110, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001, 5'b10001,   // 'A'
	5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10001, 5'b10001, 5'b11110,   // 'B'
	5'b01110, 5'b10001, 5'b10000, 5'b10000, 5'b10000, 5'b10001, 5'b01110,   // 'C'
	5'b11100, 5'b10010, 5'b10001, 5'b10001, 5'b10001, 5'b10010, 5'b11100,   // 'D'
	5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b11111,   // 'E'
	5'b11111, 5'b10000, 5'b10000, 5'b11110, 5'b10000, 5'b10000, 5'b10000,   // 'F'
	5'b01110, 5'b10001, 5'b10000, 5'b10111, 5'b10001, 5'b10001, 5'b01111,   // 'G'
	5'b10001, 5'b10001, 5'b10001, 5'b11111, 5'b10001, 5'b10001, 5'b10001,   // 'H'
	5'b01110, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b01110,   // 'I'
	5'b00111, 5'b00010, 5'b00010, 5'b00010, 5'b00010, 5'b10010, 5'b01100,   // 'J'
	5'b10001, 5'b10010, 5'b10100, 5'b11000, 5'b10100, 5'b10010, 5'b10001,   // 'K'
	5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b10000, 5'b11111,   // 'L'
	5'b10001, 5'b11011, 5'b10101, 5'b10101, 5'b10001, 5'b10001, 5'b10001,   // 'M'
	5'b10001, 5'b10001, 5'b11001, 5'b10101, 5'b10011, 5'b10001, 5'b10001,   // 'N'
	5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110,   // 'O'
	5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10000, 5'b10000, 5'b10000,   // 'P'
	5'b01110, 5'b10001, 5'b10001, 5'b10001, 5'b10101, 5'b10010, 5'b01101,   // 'Q'
	5'b11110, 5'b10001, 5'b10001, 5'b11110, 5'b10100, 5'b10010, 5'b10001,   // 'R'
	5'b01111, 5'b10000, 5'b10000, 5'b01110, 5'b00001, 5'b00001, 5'b11110,   // 'S'
	5'b11111, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100,   // 'T'
	5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01110,   // 'U'
	5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b10001, 5'b01010, 5'b00100,   // 'V'
	5'b10001, 5'b10001, 5'b10001, 5'b10101, 5'b10101, 5'b10101, 5'b01010,   // 'W'
	5'b10001, 5'b10001, 5'b01010, 5'b00100, 5'b01010, 5'b10001, 5'b10001,   // 'X'
	5'b10001, 5'b10001, 5'b01010, 5'b00100, 5'b00100, 5'b00100, 5'b00100,   // 'Y'
	5'b11111, 5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000, 5'b11111,   // 'Z'
	5'b00000, 5'b00000, 5'b00000, 5'b00000, 5'b00000, 5'b00000, 5'b00000,   // ' '
	5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00100, 5'b00000, 5'b00100   // '!'
};

// text lines : line = { gameState , 0..3 }
logic [0:15][8:0] LINE_Y     = {9'd96,9'd232,9'd272,9'd312,9'd12,9'd12,9'd0,9'd12,9'd96,9'd216,9'd256,9'd312,9'd0,9'd0,9'd0,9'd0};
logic [0:15][9:0] LINE_X     = {10'd224,10'd160,10'd216,10'd248,10'd12,10'd516,10'd0,10'd256,10'd176,10'd240,10'd248,10'd144,10'd0,10'd0,10'd0,10'd0};
logic [0:15][1:0] LINE_SHIFT = {2'd2,2'd1,2'd1,2'd1,2'd1,2'd1,2'd1,2'd1,2'd2,2'd1,2'd1,2'd1,2'd1,2'd1,2'd1,2'd1};   // 1 : font x2 , 2 : font x4
logic [0:15][4:0] LINE_LEN   = {5'd6,5'd20,5'd13,5'd9,5'd10,5'd7,5'd0,5'd8,5'd9,5'd10,5'd9,5'd22,5'd0,5'd0,5'd0,5'd0};   // characters
logic [0:15][7:0] LINE_COLOR = {8'hFC,8'hFE,8'h1F,8'hFC,8'hFE,8'hFE,8'h00,8'hE0,8'hE0,8'hFE,8'hFC,8'hFE,8'h00,8'h00,8'h00,8'h00};
logic [0:15][1:0] LINE_FX    = {2'd2,2'd1,2'd0,2'd0,2'd0,2'd0,2'd0,2'd0,2'd0,2'd0,2'd0,2'd1,2'd0,2'd0,2'd0,2'd0};   // 0 steady , 1 blinking , 2 rainbow
// event messages : entry = msgId * 2 + ( 0 title x4 at MSG_TITLE_Y , 1 subtitle x2 at MSG_SUB_Y )
logic [0:31][9:0] MSG_X     = {10'd320,10'd320,10'd278,10'd227,10'd198,10'd227,10'd86,10'd267,10'd102,10'd267,10'd198,10'd235,10'd150,10'd251,10'd214,10'd243,10'd134,10'd243,10'd102,10'd251,10'd134,10'd235,10'd320,10'd320,10'd320,10'd320,10'd320,10'd320,10'd320,10'd320,10'd320,10'd320};
logic [0:31][4:0] MSG_LEN   = {5'd0,5'd0,5'd3,5'd12,5'd8,5'd12,5'd15,5'd7,5'd14,5'd7,5'd8,5'd11,5'd11,5'd9,5'd7,5'd10,5'd12,5'd10,5'd14,5'd9,5'd12,5'd11,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0,5'd0};
logic [0:31][7:0] MSG_COLOR = {8'h00,8'h00,8'h1C,8'hFE,8'hFC,8'hFE,8'h9F,8'hFE,8'hE0,8'hFE,8'hFC,8'hFE,8'hFE,8'hFC,8'h1F,8'hFE,8'hF4,8'hFE,8'hE3,8'hFE,8'h1F,8'hFE,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
logic [0:31][0:19][5:0] MSG_TEXT = {
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 0 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 1 ""
	{6'd16,6'd24,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 2 "GO!"
	{6'd8,6'd36,6'd30,6'd25,6'd36,6'd36,6'd2,6'd36,6'd13,6'd24,6'd32,6'd23,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 3 "8 UP  2 DOWN"
	{6'd21,6'd14,6'd31,6'd14,6'd21,6'd36,6'd56,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 4 "LEVEL @!"
	{6'd15,6'd10,6'd28,6'd29,6'd14,6'd27,6'd36,6'd25,6'd18,6'd25,6'd14,6'd28,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 5 "FASTER PIPES"
	{6'd18,6'd23,6'd31,6'd18,6'd28,6'd18,6'd11,6'd21,6'd14,6'd36,6'd22,6'd10,6'd35,6'd14,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36},   // 6 "INVISIBLE MAZE!"
	{6'd21,6'd14,6'd31,6'd14,6'd21,6'd36,6'd56,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 7 "LEVEL @"
	{6'd12,6'd21,6'd24,6'd28,6'd18,6'd23,6'd16,6'd36,6'd25,6'd18,6'd25,6'd14,6'd28,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 8 "CLOSING PIPES!"
	{6'd21,6'd14,6'd31,6'd14,6'd21,6'd36,6'd56,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 9 "LEVEL @"
	{6'd21,6'd14,6'd31,6'd14,6'd21,6'd36,6'd56,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 10 "LEVEL @!"
	{6'd20,6'd14,6'd14,6'd25,6'd36,6'd16,6'd24,6'd18,6'd23,6'd16,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 11 "KEEP GOING!"
	{6'd23,6'd18,6'd16,6'd17,6'd29,6'd36,6'd22,6'd24,6'd13,6'd14,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 12 "NIGHT MODE!"
	{6'd5,6'd36,6'd28,6'd14,6'd12,6'd24,6'd23,6'd13,6'd28,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 13 "5 SECONDS"
	{6'd28,6'd17,6'd18,6'd14,6'd21,6'd13,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 14 "SHIELD!"
	{6'd1,6'd0,6'd36,6'd28,6'd14,6'd12,6'd24,6'd23,6'd13,6'd28,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 15 "10 SECONDS"
	{6'd28,6'd21,6'd24,6'd32,6'd36,6'd22,6'd24,6'd29,6'd18,6'd24,6'd23,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 16 "SLOW MOTION!"
	{6'd1,6'd0,6'd36,6'd28,6'd14,6'd12,6'd24,6'd23,6'd13,6'd28,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 17 "10 SECONDS"
	{6'd27,6'd14,6'd31,6'd14,6'd27,6'd28,6'd14,6'd13,6'd36,6'd20,6'd14,6'd34,6'd28,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 18 "REVERSED KEYS!"
	{6'd7,6'd36,6'd28,6'd14,6'd12,6'd24,6'd23,6'd13,6'd28,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 19 "7 SECONDS"
	{6'd25,6'd18,6'd25,6'd14,6'd36,6'd11,6'd27,6'd24,6'd20,6'd14,6'd23,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 20 "PIPE BROKEN!"
	{6'd28,6'd17,6'd18,6'd14,6'd21,6'd13,6'd36,6'd30,6'd28,6'd14,6'd13,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 21 "SHIELD USED"
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 22 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 23 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 24 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 25 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 26 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 27 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 28 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 29 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 30 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36}   // 31 ""
};
logic [0:15][0:31][5:0] LINE_TEXT = {
	{6'd27,6'd14,6'd10,6'd13,6'd34,6'd37,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 0 "READY!"
	{6'd25,6'd27,6'd14,6'd28,6'd28,6'd36,6'd14,6'd23,6'd29,6'd14,6'd27,6'd36,6'd29,6'd24,6'd36,6'd28,6'd29,6'd10,6'd27,6'd29,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 1 "PRESS ENTER TO START"
	{6'd8,6'd36,6'd30,6'd25,6'd36,6'd36,6'd36,6'd2,6'd36,6'd13,6'd24,6'd32,6'd23,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 2 "8 UP   2 DOWN"
	{6'd11,6'd14,6'd28,6'd29,6'd36,6'd52,6'd53,6'd54,6'd55,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 3 "BEST ~~~~"
	{6'd28,6'd12,6'd24,6'd27,6'd14,6'd36,6'd48,6'd49,6'd50,6'd51,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 4 "SCORE ^^^^"
	{6'd21,6'd14,6'd31,6'd14,6'd21,6'd36,6'd56,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 5 "LEVEL @"
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 6 ""
	{6'd27,6'd14,6'd31,6'd14,6'd27,6'd28,6'd14,6'd13,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 7 "REVERSED"
	{6'd16,6'd10,6'd22,6'd14,6'd36,6'd24,6'd31,6'd14,6'd27,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 8 "GAME OVER"
	{6'd28,6'd12,6'd24,6'd27,6'd14,6'd36,6'd48,6'd49,6'd50,6'd51,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 9 "SCORE ^^^^"
	{6'd11,6'd14,6'd28,6'd29,6'd36,6'd52,6'd53,6'd54,6'd55,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 10 "BEST ~~~~"
	{6'd25,6'd27,6'd14,6'd28,6'd28,6'd36,6'd14,6'd23,6'd29,6'd14,6'd27,6'd36,6'd29,6'd24,6'd36,6'd27,6'd14,6'd28,6'd29,6'd10,6'd27,6'd29,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 11 "PRESS ENTER TO RESTART"
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 12 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 13 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36},   // 14 ""
	{6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36,6'd36}   // 15 ""
};
// ---- end of generated tables ----

//////////--------------------------------------------------------------------------------------------------------------=
// slow frame counters for the effects
logic [5:0] blinkCount ;
logic       blinkOn ;          // blinking lines are shown only while this is 1
logic [2:0] rainbowCount ;
logic [2:0] rainbowIndex ;     // the rainbow color of now

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		blinkCount   <= 6'd0 ;
		blinkOn      <= 1'b1 ;
		rainbowCount <= 3'd0 ;
		rainbowIndex <= 3'd0 ;
	end
	else if (startOfFrame) begin
		if (blinkCount == BLINK_FRAMES - 6'd1) begin
			blinkCount <= 6'd0 ;
			blinkOn    <= !blinkOn ;
		end
		else
			blinkCount <= blinkCount + 6'd1 ;

		rainbowCount <= rainbowCount + 3'd1 ;
		if (rainbowCount == 3'd7)                       // rainbow : the next color every 8 frames
			rainbowIndex <= rainbowIndex + 3'd1 ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 1 : which text line is at this pixel , and where inside it ?

// the pixel ( x , y ) is inside the box that starts at ( boxX , boxY )
function automatic logic inBox (input int x, input int y, input int boxX, input int boxY, input int width, input int height);
	return (x >= boxX) && (x < boxX + width) && (y >= boxY) && (y < boxY + height) ;
endfunction

// the lines of the state that are shown now : in PLAY line 2 is not used and line 3 ( REVERSED ) only while the keys are swapped
logic [3:0] lineShown ;
assign lineShown = (gameState == STATE_PLAY) ? {invertControls, 1'b0, 2'b11} : 4'b1111 ;

int         px , py ;          // the pixel
int         line , entry ;     // table indexes
int         cellSize ;         // the cell size of a line : 16 small , 32 big
logic       hit ;              // the pixel is inside a text line
logic       isMsg ;            // it is the event message ( else a line of the state )
logic       big ;              // big text
logic [3:0] lineIndex ;        // the line ( 4 x gameState + k )
logic [4:0] msgEntry ;         // the message line
logic [9:0] relX ;             // the pixel inside the line box
logic [4:0] relY ;

always_comb
begin
	px = int'(pixelX) ;
	py = int'(pixelY) ;
	hit = 1'b0 ;  isMsg = 1'b0 ;  big = 1'b0 ;  relX = 10'd0 ;  relY = 5'd0 ;
	lineIndex = {gameState, 2'd0} ;
	msgEntry  = {msgId, 1'b0} ;
	line = 0 ;  entry = 0 ;  cellSize = 16 ;

	// 1. the event message ( only in PLAY ) : a big title and a small line under it
	if ((gameState == STATE_PLAY) && (msgId != 4'd0)) begin
		entry = 2 * int'(msgId) ;                                                  // the title
		if (inBox(px, py, int'(MSG_X[entry]), MSG_TITLE_Y, 32 * int'(MSG_LEN[entry]), 32)) begin
			hit = 1'b1 ;  isMsg = 1'b1 ;  big = 1'b1 ;  msgEntry = 5'(entry) ;
			relX = 10'(px - int'(MSG_X[entry])) ;
			relY = 5'(py - MSG_TITLE_Y) ;
		end
		entry = 2 * int'(msgId) + 1 ;                                              // the line under it
		if (inBox(px, py, int'(MSG_X[entry]), MSG_SUB_Y, 16 * int'(MSG_LEN[entry]), 16)) begin
			hit = 1'b1 ;  isMsg = 1'b1 ;  big = 1'b0 ;  msgEntry = 5'(entry) ;
			relX = 10'(px - int'(MSG_X[entry])) ;
			relY = 5'(py - MSG_SUB_Y) ;
		end
	end

	// 2. the 4 lines of the game state - they are checked after the message , so they are drawn over it .
	//    line 0 is checked last , so it wins if two lines overlap
	for (int k = 3; k >= 0; k--) begin
		line = 4 * int'(gameState) + k ;
		cellSize = (LINE_SHIFT[line] == 2'd2) ? 32 : 16 ;
		if (lineShown[k] && inBox(px, py, int'(LINE_X[line]), int'(LINE_Y[line]), cellSize * int'(LINE_LEN[line]), cellSize)) begin
			hit = 1'b1 ;  isMsg = 1'b0 ;  big = (cellSize == 32) ;  lineIndex = 4'(line) ;
			relX = 10'(px - int'(LINE_X[line])) ;
			relY = 5'(py - int'(LINE_Y[line])) ;
		end
	end
end

// stage 1 register : the character of the line and the font pixel inside it
logic       hit_d ;
logic       isMsg_d ;
logic [3:0] lineIndex_d ;
logic [4:0] msgEntry_d ;
logic [4:0] charIndex_d ;      // which character of the line
logic [2:0] col_d ;            // the font column inside the cell ( 0..7 )
logic [2:0] row_d ;            // the font row inside the cell ( 0..7 )

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		hit_d       <= 1'b0 ;
		isMsg_d     <= 1'b0 ;
		lineIndex_d <= 4'd0 ;
		msgEntry_d  <= 5'd0 ;
		charIndex_d <= 5'd0 ;
		col_d       <= 3'd0 ;
		row_d       <= 3'd0 ;
	end
	else begin
		hit_d       <= hit ;
		isMsg_d     <= isMsg ;
		lineIndex_d <= lineIndex ;
		msgEntry_d  <= msgEntry ;
		if (big) begin                                 // big text : cells of 32 , font pixels of 4x4
			charIndex_d <= 5'(relX / 10'd32) ;
			col_d       <= 3'((relX / 10'd4) % 10'd8) ;
			row_d       <= 3'(relY / 5'd4) ;
		end
		else begin                                     // small text : cells of 16 , font pixels of 2x2
			charIndex_d <= 5'(relX / 10'd16) ;
			col_d       <= 3'((relX / 10'd2) % 10'd8) ;
			row_d       <= 3'(relY / 5'd2) ;
		end
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 2 : the character code -> the font -> is this font pixel on ?
logic [0:31][5:0] lineText ;   // the codes of the line
logic [0:19][5:0] msgText ;    // the codes of the message line
logic [0:6][4:0]  glyph ;      // the 7 rows of the letter
logic [5:0] code ;             // the character code
logic [3:0] digit ;            // a digit of a number
logic [5:0] glyphCode ;        // the font entry to draw
logic [4:0] glyphRow ;         // the row of the letter at this pixel
logic [4:0] shadowRow ;        // the row above it ( for the shadow )
logic       fontPixel ;        // a pixel of the letter
logic       shadowPixel ;      // a pixel of the shadow

assign lineText = LINE_TEXT[lineIndex_d] ;
assign msgText  = MSG_TEXT[msgEntry_d] ;
assign code     = isMsg_d ? ((charIndex_d < 5'd20) ? msgText[charIndex_d] : SPACE_CODE) : lineText[charIndex_d] ;

// numbers : the codes 48..56 mean "a digit of a number" ( the number changes during the game ) :
//   48..51 the score ( thousands first ) , 52..55 the best score , 56 the level ( 1..8 on the screen )
//   a BCD digit is already the font code of that digit ( 0..9 ) - no conversion needed
logic [3:0] numberDigit [0:8] ;
assign numberDigit[0] = scoreBCD[15:12] ;
assign numberDigit[1] = scoreBCD[11:8] ;
assign numberDigit[2] = scoreBCD[7:4] ;
assign numberDigit[3] = scoreBCD[3:0] ;
assign numberDigit[4] = highScoreBCD[15:12] ;
assign numberDigit[5] = highScoreBCD[11:8] ;
assign numberDigit[6] = highScoreBCD[7:4] ;
assign numberDigit[7] = highScoreBCD[3:0] ;
assign numberDigit[8] = {1'b0, level} + 4'd1 ;          // the player sees LEVEL 1 .. 8

always_comb
begin
	digit = 4'd0 ;
	if ((code >= 6'd48) && (code <= 6'd56))
		digit = numberDigit[4'(code - 6'd48)] ;

	if (code >= 6'd48)
		glyphCode = {2'b0, digit} ;           // a number digit
	else if (code > LAST_CODE)
		glyphCode = SPACE_CODE ;              // a code that is not in the font
	else
		glyphCode = code ;
end

assign glyph     = FONT[glyphCode] ;
assign glyphRow  = glyph[(row_d == 3'd7) ? 3'd0 : row_d] ;           // row 7 of the cell is empty ( the space under the letter )
assign shadowRow = glyph[(row_d == 3'd0) ? 3'd0 : row_d - 3'd1] ;    // the letter row above this row

// the letter is in columns 0..4 and rows 0..6 of the cell ( bit 4 of a font row is the left pixel )
assign fontPixel   = (col_d < 3'd5) && (row_d < 3'd7) && glyphRow[3'd4 - col_d] ;
// the shadow : the letter moved one font pixel right and down - so look at the pixel up-left of this one
assign shadowPixel = (col_d >= 3'd1) && (col_d <= 3'd5) && (row_d >= 3'd1) && shadowRow[3'd5 - col_d] ;

// stage 2 register : the color
logic [7:0] RGB_d ;
logic       isHud_d ;          // the text belongs to PLAY ( the HUD or a message )

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		RGB_d   <= TRANSPARENT_ENCODING ;
		isHud_d <= 1'b0 ;
	end
	else begin
		RGB_d   <= TRANSPARENT_ENCODING ;                       // default : nothing
		isHud_d <= (lineIndex_d[3:2] == STATE_PLAY) || isMsg_d ;  // lineIndex / 4 = the game state of the line
		if (hit_d && isMsg_d) begin
			// the event message : the color of its table entry
			if (fontPixel)
				RGB_d <= MSG_COLOR[msgEntry_d] ;
			else if (shadowPixel)
				RGB_d <= SHADOW_COLOR ;
		end
		else if (hit_d) begin
			// a line of the state : blinking ( off half of the time ) , rainbow or a steady color
			if ((LINE_FX[lineIndex_d] == FX_BLINK) && !blinkOn)
				RGB_d <= TRANSPARENT_ENCODING ;
			else if (fontPixel)
				RGB_d <= (LINE_FX[lineIndex_d] == FX_RAINBOW) ? rainbowColor(rainbowIndex) : LINE_COLOR[lineIndex_d] ;
			else if (shadowPixel)
				RGB_d <= SHADOW_COLOR ;
		end
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// outputs : one color , two drawing requests ( the mux shows the overlay only in START / GAME_OVER )
assign textRGB               = RGB_d ;
assign hudDrawingRequest     = (RGB_d != TRANSPARENT_ENCODING) &&  isHud_d ;
assign overlayDrawingRequest = (RGB_d != TRANSPARENT_ENCODING) && !isHud_d ;

endmodule