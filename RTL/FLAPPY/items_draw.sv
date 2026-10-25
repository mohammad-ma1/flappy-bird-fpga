// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// items_draw : draws the coins and the rare items of the pipes ( positions from pipes_controller )
//
//   every item is a 16x16 picture :
//     edge coin : in the middle of the pipe column ( pipeX + 16 ) ,
//                 2 pixels below the upper tube ( top ) or 2 pixels above the lower tube ( bottom )
//     item      : at ( itemX , itemY ) , in the open space before the pipe - a coin , or a rare item :
//                   shield    : a gold ring with a cyan outline
//                   hourglass : a wooden frame , glass and yellow sand
//                   trap      : a purple ball with a pink center
//   the shapes are computed , not stored : circles with the squared distance from the center ,
//   the hourglass with two triangles
//   every kind has its own drawing request , so the collision detector knows what the bird touched
//   two registered stages = 2 clocks latency , like every drawing module

module	items_draw	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	signed [10:0] pixelX,             // the current VGA pixel
	input	logic	signed [10:0] pixelY,
	input	logic	signed [11:0] pipeX     [0:5],    // from pipes_controller
	input	logic	       [8:0]  gapTop    [0:5],
	input	logic	       [8:0]  gapBottom [0:5],
	input	logic	              broken    [0:5],    // a broken pipe has no edge coin
	input	logic	       [1:0]  edgeCoin  [0:5],    // 0 none , 1 top , 2 bottom
	input	logic	              itemOn    [0:5],
	input	logic	       [1:0]  itemKind  [0:5],    // 0 coin , 1 shield , 2 hourglass , 3 trap
	input	logic	signed [11:0] itemX     [0:5],
	input	logic	       [8:0]  itemY     [0:5],

	output	logic	coinDrawingRequest,
	output	logic	[7:0] coinRGB,
	output	logic	shieldItemDrawingRequest,
	output	logic	[7:0] shieldItemRGB,
	output	logic	hourglassDrawingRequest,
	output	logic	[7:0] hourglassRGB,
	output	logic	confuseDrawingRequest,           // the purple trap
	output	logic	[7:0] confuseRGB
);

parameter int NUM_PIPES  = 6;
parameter int COIN_X     = 16;    // the edge coin is 16 pixels right of the pipe edge ( the middle of the 48 pixel column )
parameter int EDGE_SPACE = 2;     // pixels between an edge coin and its tube

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;
localparam logic [1:0] EDGE_TOP       = 2'd1 ;
localparam logic [1:0] EDGE_BOTTOM    = 2'd2 ;
localparam logic [1:0] KIND_COIN      = 2'd0 ;
localparam logic [1:0] KIND_SHIELD    = 2'd1 ;
localparam logic [1:0] KIND_HOURGLASS = 2'd2 ;
localparam logic [1:0] KIND_TRAP      = 2'd3 ;

// colors , RGB 3-3-2
localparam logic [7:0] COIN_OUTLINE   = 8'hA8 ;  // brown
localparam logic [7:0] COIN_BODY      = 8'hFC ;  // gold
localparam logic [7:0] COIN_MARK      = 8'hF0 ;  // orange
localparam logic [7:0] SHIELD_OUTLINE = 8'h1F ;  // cyan
localparam logic [7:0] SHIELD_RING    = 8'hF8 ;  // gold
localparam logic [7:0] SHIELD_CENTER  = 8'hFE ;  // white
localparam logic [7:0] GLASS_FRAME    = 8'h8C ;  // brown wood
localparam logic [7:0] GLASS_EDGE     = 8'hB6 ;  // light grey glass
localparam logic [7:0] GLASS_EMPTY    = 8'hDF ;  // very light cyan
localparam logic [7:0] GLASS_SAND     = 8'hFC ;  // yellow sand
localparam logic [7:0] TRAP_EDGE      = 8'h42 ;  // dark purple
localparam logic [7:0] TRAP_BODY      = 8'hA3 ;  // purple
localparam logic [7:0] TRAP_CENTER    = 8'hE7 ;  // pink

//////////--------------------------------------------------------------------------------------------------------------=
// stage 1 ( combinational ) : is the pixel inside one of the 16x16 boxes ? which kind , and where inside the box ?
//   for every pipe : the box of its edge coin and the box of its item ( 12 box tests in parallel )
logic       hit ;
logic [1:0] kind ;
logic [3:0] ox , oy ;      // the pixel inside the box , 0..15
int         boxX , boxY ;  // top left corner of the box being tested

always_comb
begin
	hit = 1'b0 ;  kind = KIND_COIN ;  ox = 4'd0 ;  oy = 4'd0 ;
	boxX = 0 ;  boxY = 0 ;
	for (int i = 0; i < NUM_PIPES; i++) begin
		// the edge coin of pipe i
		boxX = int'(pipeX[i]) + COIN_X ;
		boxY = (edgeCoin[i] == EDGE_BOTTOM) ? int'(gapBottom[i]) - EDGE_SPACE - 16 : int'(gapTop[i]) + EDGE_SPACE ;
		if ((edgeCoin[i] == EDGE_TOP || edgeCoin[i] == EDGE_BOTTOM) && !broken[i]
		    && (int'(pixelX) >= boxX) && (int'(pixelX) < boxX + 16) && (int'(pixelY) >= boxY) && (int'(pixelY) < boxY + 16)) begin
			hit  = 1'b1 ;
			kind = KIND_COIN ;
			ox   = 4'(int'(pixelX) - boxX) ;
			oy   = 4'(int'(pixelY) - boxY) ;
		end
		// the item of pipe i
		boxX = int'(itemX[i]) ;
		boxY = int'(itemY[i]) ;
		if (itemOn[i]
		    && (int'(pixelX) >= boxX) && (int'(pixelX) < boxX + 16) && (int'(pixelY) >= boxY) && (int'(pixelY) < boxY + 16)) begin
			hit  = 1'b1 ;
			kind = itemKind[i] ;
			ox   = 4'(int'(pixelX) - boxX) ;
			oy   = 4'(int'(pixelY) - boxY) ;
		end
	end
end

// stage 1 register
logic       hit_d ;
logic [1:0] kind_d ;
logic [3:0] ox_d , oy_d ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		hit_d <= 1'b0 ;  kind_d <= KIND_COIN ;  ox_d <= '0 ;  oy_d <= '0 ;
	end
	else begin
		hit_d  <= hit && (pixelX >= 0) && (pixelX < 640) && (pixelY >= 0) && (pixelY < 480) ;
		kind_d <= kind ;
		ox_d   <= ox ;
		oy_d   <= oy ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 2 ( combinational ) : the shapes
//   the center of a 16x16 box is at 7.5 , not on a pixel . so we measure the distance from the center in HALF pixels :
//   cx = 2*ox - 15 ( -15 , -13 .. 13 , 15 ) - then the shape is exactly symmetric
//   a circle of radius R pixels : cx^2 + cy^2 <= ( 2R )^2  - no square root needed
int   cx , cy ;          // distance from the center , in half pixels
int   ax , ay ;          // |cx| , |cy|
int   r2 ;               // cx^2 + cy^2
logic inCircle ;         // inside the circle of radius 7.5 pixels ( 15 half pixels )
logic [7:0] coinColor , shieldColor , glassColor , trapColor ;

always_comb
begin
	cx = 2 * int'(ox_d) - 15 ;
	cy = 2 * int'(oy_d) - 15 ;
	ax = (cx < 0) ? -cx : cx ;
	ay = (cy < 0) ? -cy : cy ;
	r2 = cx * cx + cy * cy ;
	inCircle = (r2 <= 15 * 15) ;

	// the coin : a gold circle , a brown outline ( the last pixel , radius 6.5 .. 7.5 ) and an orange bar in the middle
	if (r2 > 13 * 13)
		coinColor = COIN_OUTLINE ;
	else if ((ax <= 3) && (ay <= 9))
		coinColor = COIN_MARK ;
	else
		coinColor = COIN_BODY ;

	// the shield : a cyan outline , a gold ring , a white center ( radius 4.5 )
	if (r2 > 13 * 13)
		shieldColor = SHIELD_OUTLINE ;
	else if (r2 > 9 * 9)
		shieldColor = SHIELD_RING ;
	else
		shieldColor = SHIELD_CENTER ;

	// the hourglass : wooden bars at the top and the bottom , two glass triangles ( |x| <= |y| ) that meet in the middle ,
	// sand in the bottom half and a thin stream of sand through the middle
	if (ay >= 13)                                     // rows 0 , 1 , 14 , 15 : the wooden frame
		glassColor = (ax <= 11) ? GLASS_FRAME : TRANSPARENT_ENCODING ;
	else if (ax > ay)
		glassColor = TRANSPARENT_ENCODING ;           // outside the two triangles
	else if (ax + 2 > ay)
		glassColor = GLASS_EDGE ;                     // the edge of the glass
	else if ((cy > 0) && (ay >= 5))
		glassColor = GLASS_SAND ;                     // the sand pile in the bottom half
	else if (ax <= 1)
		glassColor = GLASS_SAND ;                     // the falling stream
	else
		glassColor = GLASS_EMPTY ;

	// the trap : a dark purple edge , a purple ball , a pink center ( radius 2.5 )
	if (r2 > 13 * 13)
		trapColor = TRAP_EDGE ;
	else if (r2 > 5 * 5)
		trapColor = TRAP_BODY ;
	else
		trapColor = TRAP_CENTER ;
end

// stage 2 register : only the output of the found kind gets a color
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		coinRGB       <= TRANSPARENT_ENCODING ;
		shieldItemRGB <= TRANSPARENT_ENCODING ;
		hourglassRGB  <= TRANSPARENT_ENCODING ;
		confuseRGB    <= TRANSPARENT_ENCODING ;
	end
	else begin
		coinRGB       <= TRANSPARENT_ENCODING ;   // defaults : nothing
		shieldItemRGB <= TRANSPARENT_ENCODING ;
		hourglassRGB  <= TRANSPARENT_ENCODING ;
		confuseRGB    <= TRANSPARENT_ENCODING ;
		if (hit_d) begin
			case (kind_d)
				KIND_COIN:      if (inCircle) coinRGB       <= coinColor ;
				KIND_SHIELD:    if (inCircle) shieldItemRGB <= shieldColor ;
				KIND_HOURGLASS: hourglassRGB <= glassColor ;     // not round : the whole box ( the corners are transparent )
				KIND_TRAP:      if (inCircle) confuseRGB    <= trapColor ;
			endcase
		end
	end
end

assign coinDrawingRequest       = (coinRGB       != TRANSPARENT_ENCODING) ;
assign shieldItemDrawingRequest = (shieldItemRGB != TRANSPARENT_ENCODING) ;
assign hourglassDrawingRequest  = (hourglassRGB  != TRANSPARENT_ENCODING) ;
assign confuseDrawingRequest    = (confuseRGB    != TRANSPARENT_ENCODING) ;

endmodule
