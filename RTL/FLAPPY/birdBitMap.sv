// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// birdBitMap : the 32x32 bitmap of the bird , 2 animation frames ( wing up / wing down )
// written like the course smileyBitMap ( Lab1Demo RTL/VGA/smileyBitMap.sv ) :
//   inputs  : offsetX / offsetY inside the bracket and InsideRectangle , from the course square_object
//   outputs : drawingRequest / RGBout , one registered stage , 8'hFF in the bitmap = transparent
// the course smiley reads its colors from a MIF file ( lpm_rom ) ; the bird is small , so its colors are in tables
// here ( a 4 bit color index per pixel + a 16 color table ) - the same idea , no MIF file needed

module	birdBitMap	(
					input	logic	clk,
					input	logic	resetN,
// the bracket is 32x32 : only the 5 LSBs of the offsets are used
					input	logic	[10:0] offsetX,       // offset from the top left position ( from square_object )
					input	logic	[10:0] offsetY,
					input	logic	InsideRectangle,      // the pixel is inside the bracket ( from square_object )
					input	logic	flapFrame,            // 0 wing up , 1 wing down ( from flappy_bird_logic )

					output	logic	drawingRequest,       // the pixel should be displayed
					output	logic	[7:0] RGBout          // rgb value from the bitmap
);

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;   // RGB value in the bitmap representing a transparent pixel

// the tables below use ascending ranges [0:N] like the course bitmaps : row 0 is the top row , pixel 0 the left one
// they are constant tables ( initialized and never written ) - Quartus builds them as ROM / logic

// colors table : the bitmap holds a 4 bit color index per pixel ( half the memory of 8 bit RGB per pixel )
// RGB 3-3-2 : [7:5] RED , [4:2] GREEN , [1:0] BLUE
logic [0:15][7:0] COLOR_TABLE = {
	8'hFF,   // 0 transparent
	8'h00,   // 1 black outline
	8'hFC,   // 2 yellow body
	8'hFE,   // 3 white eye   ( 8'hFF is reserved for transparent )
	8'hF0,   // 4 orange beak
	8'hE0,   // 5 red mouth
	8'hFE,   // 6 white wing
	8'hD8,   // 7 dark yellow belly
	8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF  // 8..15 not used
};

// the bitmaps : one line per row , one hex digit ( color index ) per pixel , left pixel = first digit
logic [0:31][0:31][3:0] BIRD_WING_UP = {
		128'h00000000000000000000000000000000,   //  0
		128'h00000000000000000000000000000000,   //  1
		128'h00000000000000000000000000000000,   //  2
		128'h00000000000000000000000000000000,   //  3
		128'h00000000000000000000000000000000,   //  4
		128'h00000000000000000000000000000000,   //  5
		128'h00000000000000000000000000000000,   //  6
		128'h00000000000000000000000000000000,   //  7
		128'h00000000000000011111111000000000,   //  8
		128'h00000000000001122222133110000000,   //  9
		128'h00000000000012222221333331000000,   // 10
		128'h00000000000122222213333333100000,   // 11
		128'h00000011110122222133333133100000,   // 12
		128'h00000166661122222133333133100000,   // 13
		128'h00001666666122222133333133100000,   // 14
		128'h00001666666612222213333333100000,   // 15
		128'h00001266666122222221111111110000,   // 16
		128'h00000122221222222214444444441000,   // 17
		128'h00000011117722222141111111110000,   // 18
		128'h00000001777777771555555551000000,   // 19
		128'h00000001777777777144444444100000,   // 20
		128'h00000000117777777711111111000000,   // 21
		128'h00000000001111111100000000000000,   // 22
		128'h00000000000000000000000000000000,   // 23
		128'h00000000000000000000000000000000,   // 24
		128'h00000000000000000000000000000000,   // 25
		128'h00000000000000000000000000000000,   // 26
		128'h00000000000000000000000000000000,   // 27
		128'h00000000000000000000000000000000,   // 28
		128'h00000000000000000000000000000000,   // 29
		128'h00000000000000000000000000000000,   // 30
		128'h00000000000000000000000000000000   // 31
};

logic [0:31][0:31][3:0] BIRD_WING_DOWN = {
		128'h00000000000000000000000000000000,   //  0
		128'h00000000000000000000000000000000,   //  1
		128'h00000000000000000000000000000000,   //  2
		128'h00000000000000000000000000000000,   //  3
		128'h00000000000000000000000000000000,   //  4
		128'h00000000000000000000000000000000,   //  5
		128'h00000000000000000000000000000000,   //  6
		128'h00000000000000000000000000000000,   //  7
		128'h00000000000000011111111000000000,   //  8
		128'h00000000000001122222133110000000,   //  9
		128'h00000000000012222221333331000000,   // 10
		128'h00000000000122222213333333100000,   // 11
		128'h00000000000122222133333133100000,   // 12
		128'h00000000001222222133333133100000,   // 13
		128'h00000000012222222133333133100000,   // 14
		128'h00000111112222222213333333100000,   // 15
		128'h00001666661222222221111111110000,   // 16
		128'h00016666666122222214444444441000,   // 17
		128'h00016666661772222141111111110000,   // 18
		128'h00001166617777771555555551000000,   // 19
		128'h00000011177777777144444444100000,   // 20
		128'h00000000117777777711111111000000,   // 21
		128'h00000000001111111100000000000000,   // 22
		128'h00000000000000000000000000000000,   // 23
		128'h00000000000000000000000000000000,   // 24
		128'h00000000000000000000000000000000,   // 25
		128'h00000000000000000000000000000000,   // 26
		128'h00000000000000000000000000000000,   // 27
		128'h00000000000000000000000000000000,   // 28
		128'h00000000000000000000000000000000,   // 29
		128'h00000000000000000000000000000000,   // 30
		128'h00000000000000000000000000000000   // 31
};


//////////--------------------------------------------------------------------------------------------------------------=
// the pixel of the bitmap : the 5 LSBs of the offsets ( the bracket is 32x32 )
logic [0:31][3:0] bitmapRow ;   // the current row of the bitmap
logic [3:0] colorIndex ;

assign bitmapRow  = (flapFrame == 1'b1) ? BIRD_WING_DOWN[offsetY[4:0]] : BIRD_WING_UP[offsetY[4:0]] ;
assign colorIndex = bitmapRow[offsetX[4:0]] ;

//////////--------------------------------------------------------------------------------------------------------------=
// pipeline (ff) to get the pixel color from the bitmap ( like smileyBitMap )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		RGBout <= TRANSPARENT_ENCODING ;   // nothing is drawn during reset
	end
	else begin
		RGBout <= TRANSPARENT_ENCODING ;   // default
		if (InsideRectangle == 1'b1)       // inside the bracket
			RGBout <= COLOR_TABLE[colorIndex] ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// decide if to draw the pixel or not ( the transparent color is not drawn )
assign drawingRequest = (RGBout != TRANSPARENT_ENCODING ) ? 1'b1 : 1'b0 ;

endmodule
