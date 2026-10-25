// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// pipes_draw : draws the 6 pipes of pipes_controller
//
//   a pipe is a column PIPE_WIDTH pixels wide , with a gap in it :
//     upper tube : from the top of the screen down to the row above gapTop
//     lower tube : from gapBottom down to the bottom of the screen
//   near the gap every tube has a CAP ( CAP_HEIGHT rows , the full width ) ,
//   the rest of the tube ( the BODY ) is BODY_INSET pixels narrower on each side
//   colors : a dark outline , a light stripe on the left and a dark stripe on the right ( a 3D look ) ,
//            the active pipe ( the one the player controls ) is teal , the other pipes are green
//   a broken pipe ( the shield broke it ) is not drawn
//   two registered stages = 2 clocks latency , like every drawing module

module	pipes_draw	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	signed [10:0] pixelX,             // the current VGA pixel
	input	logic	signed [10:0] pixelY,
	input	logic	signed [11:0] pipeX     [0:5],    // from pipes_controller : left edge of every pipe
	input	logic	       [8:0]  gapTop    [0:5],    // the upper tube ends just above this row
	input	logic	       [8:0]  gapBottom [0:5],    // the lower tube starts at this row
	input	logic	              broken    [0:5],    // broken pipes are not drawn
	input	logic	[2:0] activeIndex,                // the pipe the player controls

	output	logic	drawingRequest,                   // the pixel belongs to a pipe
	output	logic	[7:0] RGBout                      // its color
);

parameter int NUM_PIPES   = 6;
parameter int PIPE_WIDTH  = 48;    // the same value is in pipes_controller
parameter int CAP_HEIGHT  = 16;
parameter int BODY_INSET  = 4;     // the body is 4 pixels narrower than the cap on each side
parameter int SHADE_WIDTH = 10;    // width of the light stripe and of the dark stripe

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;

// colors , RGB 3-3-2 : [7:5] red , [4:2] green , [1:0] blue
localparam logic [7:0] GREEN_OUTLINE = 8'h04 ;   // the pipes
localparam logic [7:0] GREEN_DARK    = 8'h0C ;
localparam logic [7:0] GREEN_MID     = 8'h18 ;
localparam logic [7:0] GREEN_LIGHT   = 8'h9D ;
localparam logic [7:0] TEAL_OUTLINE  = 8'h05 ;   // the active pipe
localparam logic [7:0] TEAL_DARK     = 8'h0A ;
localparam logic [7:0] TEAL_MID      = 8'h16 ;
localparam logic [7:0] TEAL_LIGHT    = 8'h5F ;

//////////--------------------------------------------------------------------------------------------------------------=
// stage 1 ( combinational ) : which pipe is in the column of this pixel ?
//   6 comparators work in parallel , one per pipe . the pipes never overlap , so at most one is found
logic       hit ;
logic [2:0] hitPipe ;
logic       onScreen ;

assign onScreen = (pixelX >= 0) && (pixelX < 640) && (pixelY >= 0) && (pixelY < 480) ;

always_comb
begin
	hit     = 1'b0 ;
	hitPipe = 3'd0 ;
	for (int i = 0; i < NUM_PIPES; i++)
		if (!broken[i] && (int'(pixelX) >= int'(pipeX[i])) && (int'(pixelX) < int'(pipeX[i]) + PIPE_WIDTH)) begin
			hit     = 1'b1 ;
			hitPipe = 3'(i) ;
		end
end

// stage 1 register : keep only what stage 2 needs about this pixel and its pipe
logic       hit_d ;
logic [5:0] xIn_d ;          // the column inside the pipe , 0..47
logic [8:0] y_d ;            // the row
logic [8:0] top_d ;          // the gap of the pipe
logic [8:0] bottom_d ;
logic       active_d ;       // it is the active pipe

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		hit_d    <= 1'b0 ;
		xIn_d    <= '0 ;
		y_d      <= '0 ;
		top_d    <= '0 ;
		bottom_d <= '0 ;
		active_d <= 1'b0 ;
	end
	else begin
		hit_d    <= hit && onScreen ;
		xIn_d    <= 6'(int'(pixelX) - int'(pipeX[hitPipe])) ;
		y_d      <= 9'(pixelY) ;
		top_d    <= gapTop[hitPipe] ;
		bottom_d <= gapBottom[hitPipe] ;
		active_d <= (hitPipe == activeIndex) ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 2 ( combinational ) : the shape and the color of the tube at this pixel
logic upperTube , lowerTube ;    // the row is above the gap / below the gap
logic upperCap , lowerCap ;      // the row is in the cap of the tube ( the 16 rows next to the gap )
int   leftX , rightX ;           // the first and the last column of the tube in this row
logic inShape ;                  // the pixel is inside the tube
logic isOutline ;
logic [7:0] pipeColor ;

always_comb
begin
	upperTube = (y_d <  top_d) ;
	lowerTube = (y_d >= bottom_d) ;
	upperCap  = upperTube && (int'(y_d) >= int'(top_d) - CAP_HEIGHT) ;
	lowerCap  = lowerTube && (int'(y_d) <  int'(bottom_d) + CAP_HEIGHT) ;

	// the cap is the full width , the body is narrower
	if (upperCap || lowerCap) begin
		leftX  = 0 ;
		rightX = PIPE_WIDTH - 1 ;
	end
	else begin
		leftX  = BODY_INSET ;
		rightX = PIPE_WIDTH - 1 - BODY_INSET ;
	end
	inShape = (int'(xIn_d) >= leftX) && (int'(xIn_d) <= rightX) ;

	// the outline : the left and right edges , and the first and last rows of every cap
	isOutline = (int'(xIn_d) == leftX) || (int'(xIn_d) == rightX)
	         || (upperCap && ((int'(y_d) == int'(top_d) - 1) || (int'(y_d) == int'(top_d) - CAP_HEIGHT)))
	         || (lowerCap && ((y_d == bottom_d) || (int'(y_d) == int'(bottom_d) + CAP_HEIGHT - 1))) ;

	// the color : outline , light stripe on the left , dark stripe on the right , middle
	if (isOutline)
		pipeColor = active_d ? TEAL_OUTLINE : GREEN_OUTLINE ;
	else if (int'(xIn_d) < leftX + SHADE_WIDTH)
		pipeColor = active_d ? TEAL_LIGHT : GREEN_LIGHT ;
	else if (int'(xIn_d) > rightX - SHADE_WIDTH)
		pipeColor = active_d ? TEAL_DARK : GREEN_DARK ;
	else
		pipeColor = active_d ? TEAL_MID : GREEN_MID ;
end

// stage 2 register : the color of the pixel ( transparent when it is not a tube )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		RGBout <= TRANSPARENT_ENCODING ;
	else begin
		RGBout <= TRANSPARENT_ENCODING ;                  // default : nothing
		if (hit_d && (upperTube || lowerTube) && inShape)
			RGBout <= pipeColor ;
	end
end

assign drawingRequest = (RGBout != TRANSPARENT_ENCODING) ;

endmodule
