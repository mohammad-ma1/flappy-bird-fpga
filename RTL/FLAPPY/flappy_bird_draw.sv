// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// flappy_bird_draw : the bird , built from the course blocks of Lab1Demo , exactly like the smiley of the demo :
//
//      pixelX / pixelY , topLeftX / topLeftY                  offsetX / offsetY , InsideRectangle
//   ------------------------------> square_object ( course ) ------------------------------> birdBitMap -> drawingRequest , RGBout
//                                   32x32 bracket                                          ( like smileyBitMap )
//
//   square_object : RTL/VGA/square_object.sv from Lab1Demo , UNCHANGED - is the pixel inside the 32x32 bracket , and where
//   birdBitMap    : the color of that pixel from the bird bitmap ( 2 animation frames )
// latency : square_object 1 clock + birdBitMap 1 clock = 2 clocks , like every drawing module of the game

module	flappy_bird_draw	(
					input	logic	clk,
					input	logic	resetN,
					input 	logic signed	[10:0] pixelX,   // current VGA pixel
					input 	logic signed	[10:0] pixelY,
					input 	logic signed	[10:0] topLeftX, // position on the screen (from flappy_bird_logic)
					input 	logic signed	[10:0] topLeftY, // can be negative , if the object is partly outside
					input	logic	flapFrame,                // 0 wing up , 1 wing down (from flappy_bird_logic)

					output	logic	drawingRequest,  // the pixel belongs to the bird (not transparent)
					output	logic	[7:0]	RGBout      // bird color
);

logic [10:0] offsetX , offsetY ;   // the pixel inside the bracket ( from square_object )
logic        insideRectangle ;     // square_object drawingRequest = the pixel is inside the bracket
logic [7:0]  squareRGB ;           // the square color is not used - the bitmap gives the colors

square_object #(
	.OBJECT_WIDTH_X(32),
	.OBJECT_HEIGHT_Y(32) )
bird_square_inst (
	.clk(clk), .resetN(resetN),
	.pixelX(pixelX), .pixelY(pixelY),
	.topLeftX(topLeftX), .topLeftY(topLeftY),
	.offsetX(offsetX), .offsetY(offsetY),
	.drawingRequest(insideRectangle),
	.RGBout(squareRGB) );

birdBitMap bird_bitmap_inst (
	.clk(clk), .resetN(resetN),
	.offsetX(offsetX), .offsetY(offsetY),
	.InsideRectangle(insideRectangle),
	.flapFrame(flapFrame),
	.drawingRequest(drawingRequest),
	.RGBout(RGBout) );

endmodule
