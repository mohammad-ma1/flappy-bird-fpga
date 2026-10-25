// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// celestial_draw : the SUN and the MOON
//
//   level 0 ( day ) : the sun , level 1 ( sunset ) : the sun , 70 pixels lower , level 2+ ( night ) : the moon
//   they move on an ARC across the sky ( 56 seconds from left to right ) :
//     X = 64 + dayStep                     ( 64..575 : dayStep = a slow frame counter / 8 )
//     Y = 40 + ( X - 320 )^2 / 512         ( a parabola : high in the middle , low at the sides )
//   the shapes are circles . a pixel is inside a circle of radius R when dx^2 + dy^2 < R^2 ( no square root needed )
//     sun  : radius 18 , yellow inside radius 14 , an orange rim outside it
//     moon : inside a circle of radius 14 , but outside a second circle moved 7 right and 4 up -> a white crescent
//   two registered stages = 2 clocks latency , like every drawing module

module	celestial_draw	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	signed [10:0] pixelX,      // the current VGA pixel
	input	logic	signed [10:0] pixelY,
	input	logic	[8:0]  dayStep,            // the position on the path , 0..511 ( from flappy_game_controller )
	input	logic	[2:0]  level,              // sun , low sun or moon

	output	logic	drawingRequest,
	output	logic	[7:0] RGBout
);

parameter int SUN_RADIUS    = 18;
parameter int SUN_CORE      = 14;    // the yellow part of the sun
parameter int MOON_RADIUS   = 14;
parameter int MOON_SHADOW_X = 7;     // the center of the shadow circle that cuts the crescent
parameter int MOON_SHADOW_Y = -4;
parameter int SUNSET_DROP   = 70;    // the sunset sun is lower

localparam logic [7:0] TRANSPARENT_ENCODING = 8'hFF ;
localparam logic [7:0] SUN_COLOR  = 8'hFC ;   // yellow
localparam logic [7:0] SUN_RIM    = 8'hF4 ;   // orange
localparam logic [7:0] MOON_COLOR = 8'hFE ;   // white ( 8'hFF means transparent )

//////////--------------------------------------------------------------------------------------------------------------=
// stage 1 ( combinational ) : where is the sun / moon , and how far is this pixel from it ?
logic isMoon ;
int   bodyX , bodyY ;        // the center of the sun / moon
int   arcDX ;                // bodyX - 320 ( the distance from the middle of the screen )
int   dx , dy ;              // the pixel - the center
int   sx , sy ;              // the pixel - the center of the moon shadow
int   r2 , s2 ;              // the squared distances
logic inBody , inCore , inShadow ;

assign isMoon = (level >= 3'd2) ;

always_comb
begin
	bodyX = 64 + int'(dayStep) ;
	arcDX = bodyX - 320 ;
	bodyY = 40 + (arcDX * arcDX) / 512 ;
	if (level == 3'd1)
		bodyY = bodyY + SUNSET_DROP ;

	dx = int'(pixelX) - bodyX ;
	dy = int'(pixelY) - bodyY ;
	sx = dx - MOON_SHADOW_X ;
	sy = dy - MOON_SHADOW_Y ;
	r2 = dx * dx + dy * dy ;
	s2 = sx * sx + sy * sy ;

	inBody   = isMoon ? (r2 < MOON_RADIUS * MOON_RADIUS) : (r2 < SUN_RADIUS * SUN_RADIUS) ;
	inCore   = (r2 < SUN_CORE * SUN_CORE) ;
	inShadow = (s2 < MOON_RADIUS * MOON_RADIUS) ;
end

// stage 1 register
logic inBody_d , inCore_d , inShadow_d , isMoon_d ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		inBody_d <= 1'b0 ;  inCore_d <= 1'b0 ;  inShadow_d <= 1'b0 ;  isMoon_d <= 1'b0 ;
	end
	else begin
		inBody_d   <= inBody && (pixelX >= 0) && (pixelX < 640) && (pixelY >= 0) && (pixelY < 480) ;
		inCore_d   <= inCore ;
		inShadow_d <= inShadow ;
		isMoon_d   <= isMoon ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 2 register : the color
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		RGBout <= TRANSPARENT_ENCODING ;
	else begin
		RGBout <= TRANSPARENT_ENCODING ;                      // default : nothing
		if (inBody_d) begin
			if (isMoon_d)
				RGBout <= inShadow_d ? TRANSPARENT_ENCODING : MOON_COLOR ;   // the crescent
			else
				RGBout <= inCore_d ? SUN_COLOR : SUN_RIM ;
		end
	end
end

assign drawingRequest = (RGBout != TRANSPARENT_ENCODING) ;

endmodule
