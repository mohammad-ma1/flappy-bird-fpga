// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_objects_mux : chooses the ONE color of every pixel ( based on the course objects_mux )
//
//   many modules may want to draw the same pixel . the object with the highest priority wins :
//     text  >  bird  >  shield ring  >  shield item  >  hourglass  >  purple trap  >  coins  >  pipes  >  sun / moon  >  background
//   and then three effects :
//     GAME OVER  : everything but the text at half brightness
//     NIGHT MODE : only a circle in front of the bird is seen ( radius 140 , a soft edge to 160 ) , the rest is black
//     SHIELD     : a cyan ring around the bird , 18..22 pixels from its center
//   the invisible maze : the pipes are not drawn while pipesVisible is 0 ( they still kill - the collision detector
//   gets the real pipes drawing request )
//   a circle without a square root : the pixel is inside radius R when dx^2 + dy^2 < R^2
//   the drawing requests come 2 clocks after their pixel , so pixelX / pixelY are delayed by 2 clocks here
//   colors are RGB 3-3-2 : [7:5] red , [4:2] green , [1:0] blue

module	flappy_objects_mux	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	signed [10:0] pixelX,          // the current VGA pixel ( for the circles )
	input	logic	signed [10:0] pixelY,
	input	logic	[1:0] gameState,               // 0 START , 1 PLAY , 2 GAME_OVER
	input	logic	spotlightOn,                   // night mode
	input	logic	signed [10:0] spotCenterX,     // the center of the bird
	input	logic	signed [10:0] spotCenterY,
	// the text : one color , two drawing requests
	input	logic	[7:0] textRGB,
	input	logic	hudDrawingRequest,             // text of PLAY ( always shown )
	input	logic	overlayDrawingRequest,         // text of START / GAME_OVER ( shown only then )
	// the objects : a drawing request and a color for every one
	input	logic	shieldItemDrawingRequest,
	input	logic	[7:0] shieldItemRGB,
	input	logic	shieldActive,                  // draw the shield ring around the bird
	input	logic	birdDrawingRequest,
	input	logic	[7:0] birdRGB,
	input	logic	hourglassDrawingRequest,
	input	logic	[7:0] hourglassRGB,
	input	logic	confuseDrawingRequest,         // the purple trap
	input	logic	[7:0] confuseRGB,
	input	logic	coinDrawingRequest,
	input	logic	[7:0] coinRGB,
	input	logic	pipesVisible,                  // 0 : the pipes are hidden now
	input	logic	pipesDrawingRequest,
	input	logic	[7:0] pipesRGB,
	input	logic	celestialDrawingRequest,       // the sun / the moon
	input	logic	[7:0] celestialRGB,
	input	logic	[7:0] backGroundRGB,           // always drawn

	output	logic	[7:0] RGBOut                   // to the VGA_Controller
);

parameter int NIGHT_RADIUS   = 140;   // night mode : the clear circle ...
parameter int NIGHT_GLOW     = 160;   // ... and a soft edge at half brightness up to here
parameter int NIGHT_OFFSET_X = 100;   // the circle center is 100 pixels in front of ( right of ) the bird
parameter int SHIELD_INNER   = 18;    // the shield ring : 18..22 pixels from the bird center
parameter int SHIELD_OUTER   = 22;

localparam logic [1:0] STATE_PLAY      = 2'd1 ;
localparam logic [1:0] STATE_GAME_OVER = 2'd2 ;
localparam logic [7:0] SHIELD_COLOR    = 8'h1F ;   // cyan

//////////--------------------------------------------------------------------------------------------------------------=
// the pixel of the drawing requests : pixelX / pixelY of 2 clocks ago
logic signed [10:0] pixelX_d1 , pixelX_d2 , pixelY_d1 , pixelY_d2 ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		pixelX_d1 <= '0 ;  pixelX_d2 <= '0 ;  pixelY_d1 <= '0 ;  pixelY_d2 <= '0 ;
	end
	else begin
		pixelX_d1 <= pixelX ;  pixelX_d2 <= pixelX_d1 ;
		pixelY_d1 <= pixelY ;  pixelY_d2 <= pixelY_d1 ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// the circles : squared distances from the bird and from the night mode center
int   birdDX , birdDY , birdDist2 ;     // from the bird center ( the shield ring )
int   spotDX , spotDY , spotDist2 ;     // from the night mode center ( 100 pixels in front of the bird )
logic shieldRing ;                      // the pixel is on the shield ring
logic nightOn ;                         // night mode , only while playing

always_comb
begin
	birdDX    = int'(pixelX_d2) - int'(spotCenterX) ;
	birdDY    = int'(pixelY_d2) - int'(spotCenterY) ;
	birdDist2 = birdDX * birdDX + birdDY * birdDY ;

	spotDX    = int'(pixelX_d2) - (int'(spotCenterX) + NIGHT_OFFSET_X) ;
	spotDY    = int'(pixelY_d2) - int'(spotCenterY) ;
	spotDist2 = spotDX * spotDX + spotDY * spotDY ;
end

assign shieldRing = shieldActive && (birdDist2 >= SHIELD_INNER * SHIELD_INNER) && (birdDist2 <= SHIELD_OUTER * SHIELD_OUTER) ;
assign nightOn    = spotlightOn && (gameState == STATE_PLAY) ;

//////////--------------------------------------------------------------------------------------------------------------=
// the game scene : the first object ( by priority ) that wants to draw this pixel
logic [7:0] sceneRGB ;

always_comb
begin
	if (birdDrawingRequest)
		sceneRGB = birdRGB ;
	else if (shieldRing)
		sceneRGB = SHIELD_COLOR ;
	else if (shieldItemDrawingRequest)
		sceneRGB = shieldItemRGB ;
	else if (hourglassDrawingRequest)
		sceneRGB = hourglassRGB ;
	else if (confuseDrawingRequest)
		sceneRGB = confuseRGB ;
	else if (coinDrawingRequest)
		sceneRGB = coinRGB ;
	else if (pipesDrawingRequest && pipesVisible)    // the invisible maze : the pipes are skipped
		sceneRGB = pipesRGB ;
	else if (celestialDrawingRequest)
		sceneRGB = celestialRGB ;
	else
		sceneRGB = backGroundRGB ;                   // the last one , always there
end

// the scene at half brightness : every color channel divided by 2 ( shifted right by 1 bit ) , on its own -
// shifting the whole byte would move bits from one color into the next one
logic [7:0] dimRGB ;
assign dimRGB = { 1'b0, sceneRGB[7:6],      // red   / 2
                  1'b0, sceneRGB[4:3],      // green / 2
                  1'b0, sceneRGB[1]   } ;   // blue  / 2

// text on this pixel : the HUD always , the START / GAME OVER text only outside PLAY
logic isText ;
assign isText = hudDrawingRequest || (overlayDrawingRequest && (gameState != STATE_PLAY)) ;

//////////--------------------------------------------------------------------------------------------------------------=
// the output register : the text , then the effects , then the scene
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		RGBOut <= 8'h00 ;
	else begin
		if (isText)
			RGBOut <= textRGB ;                                  // the text is on top of everything , also at night
		else if (gameState == STATE_GAME_OVER)
			RGBOut <= dimRGB ;                                   // the frozen scene behind the GAME OVER text
		else if (nightOn && (spotDist2 > NIGHT_GLOW * NIGHT_GLOW))
			RGBOut <= 8'h00 ;                                    // night : dark outside the circle
		else if (nightOn && (spotDist2 >= NIGHT_RADIUS * NIGHT_RADIUS))
			RGBOut <= dimRGB ;                                   // night : the soft edge of the circle
		else
			RGBOut <= sceneRGB ;
	end
end

endmodule
