// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_background : the background picture ( always drawn , behind everything )
//
//   the scene changes with the level :
//     level 0  ( score 0..9 )   : DAY    - light blue sky , white clouds
//     level 1  ( score 10..19 ) : SUNSET - orange sky , pink clouds
//     level 2+ ( score 20 .. )  : NIGHT  - dark sky , stars , lit windows
//   when the scene changes , the colors change slowly ( 32 small steps , about 1 second ) - a blend
//
//   three layers move left at different speeds ( PARALLAX - far things move slower , it looks 3D ) :
//     clouds  : near layer , 1 pixel every frame     ( nearOffset )
//     skyline : mid layer  , 1 pixel every 2 frames  ( midOffset )
//     stars   : far layer  , 1 pixel every 4 frames  ( farOffset )
//   a layer moves by adding its offset to pixelX
//   two registered stages = 2 clocks latency , like every drawing module

module	flappy_background	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	signed [10:0] pixelX,      // the current VGA pixel
	input	logic	signed [10:0] pixelY,
	input	logic	[9:0]  farOffset,          // from parallax_layers : stars
	input	logic	[8:0]  midOffset,          //                        skyline ( it repeats every 512 pixels )
	input	logic	[7:0]  nearOffset,         //                        clouds  ( they repeat every 256 pixels )
	input	logic	startOfFrame,              // the blend makes a step once per 2 frames
	input	logic	[2:0]  level,              // 0..7 : the scene

	output	logic	[7:0] backGroundRGB        // to flappy_objects_mux
);

localparam int CLOUD_A_Y     = 48;    // top row of the first line of clouds
localparam int CLOUD_B_Y     = 128;   // top row of the second line of clouds
localparam int SKY_SPLIT_Y   = 160;   // the sky above this row is a little darker
localparam int STARS_MAX_Y   = 300;   // no stars below this row
localparam int SCREEN_BOTTOM = 480;
// the tables below use ascending ranges [0:N] like the course bitmaps : entry 0 is the first line
//                          the key colors :   day    sunset  night
logic [0:2][7:0] SKY_TOP_KEY        = { 8'h53, 8'h8E, 8'h01 } ;   // light blue , dark orange , almost black
logic [0:2][7:0] SKY_BOTTOM_KEY     = { 8'h7B, 8'hF6, 8'h06 } ;   // light blue , orange      , dark blue
logic [0:2][7:0] CLOUD_KEY          = { 8'hFE, 8'hF5, 8'h25 } ;   // white      , pink        , dark grey
logic [0:2][7:0] BUILDING_KEY       = { 8'h6D, 8'h49, 8'h24 } ;
logic [0:2][7:0] WINDOW_KEY         = { 8'h92, 8'h6E, 8'h49 } ;   // the windows when they are not lit
localparam logic [7:0] WINDOW_LIT   = 8'hF8 ;                     // yellow light at night

// building heights in pixels , 16 buildings of 32 pixels = 512 pixels , then it repeats
logic [0:15][7:0] BUILDING_HEIGHT   = { 8'd64, 8'd96, 8'd48, 8'd112, 8'd80, 8'd56, 8'd120, 8'd72,
                                        8'd88, 8'd52, 8'd104, 8'd68, 8'd92, 8'd60, 8'd116, 8'd76 } ;

// cloud bitmap 32x16 , 1 = cloud ( left pixel is the MSB )
logic [0:15][31:0] CLOUD_BITMAP = {
	32'b00000000000000000000000000000000,   //  0
	32'b00000000000111111000000000000000,   //  1
	32'b00000000011111111110000000000000,   //  2
	32'b00001111111111111110001111110000,   //  3
	32'b00011111111111111111111110111100,   //  4
	32'b00111111111111111111111111111100,   //  5
	32'b01111111111111111111111111111110,   //  6
	32'b11111111111111111111111111111111,   //  7
	32'b11111111111111111111111111111111,   //  8
	32'b01111111111111111111111111111110,   //  9
	32'b00111111111111111111111111111100,   // 10
	32'b00001111111111111111111111110000,   // 11
	32'b00000000000000000000000000000000,   // 12
	32'b00000000000000000000000000000000,   // 13
	32'b00000000000000000000000000000000,   // 14
	32'b00000000000000000000000000000000   // 15
};

//////////--------------------------------------------------------------------------------------------------------------=
// the scene and the blend
//   levelScene : the scene that the level wants ( 0 day , 1 sunset , 2 night )
//   fromScene -> toScene : the blend of now . blendStep 0..31 says how far it is . fromScene == toScene : no blend
logic [1:0] levelScene ;
logic [1:0] fromScene , toScene ;
logic [4:0] blendStep ;
logic       stepNow ;          // toggles every frame : the blend makes a step every 2nd frame
logic       isNight ;          // show stars and lit windows

assign levelScene = (level == 3'd0) ? 2'd0 : (level == 3'd1) ? 2'd1 : 2'd2 ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		fromScene <= 2'd0 ;
		toScene   <= 2'd0 ;
		blendStep <= 5'd0 ;
		stepNow   <= 1'b0 ;
	end
	else if (startOfFrame) begin
		stepNow <= !stepNow ;
		if (levelScene != toScene) begin                 // a new scene : start a blend from the scene of now
			fromScene <= toScene ;
			toScene   <= levelScene ;
			blendStep <= 5'd0 ;
		end
		else if (stepNow && (fromScene != toScene)) begin
			if (blendStep == 5'd31)
				fromScene <= toScene ;                   // the blend is over : exactly the new colors
			else
				blendStep <= blendStep + 5'd1 ;
		end
	end
end

// stars and lit windows : when the night scene is more than half way in
assign isNight = (toScene == 2'd2) && ((fromScene == 2'd2) || (blendStep >= 5'd16)) ;

// the blend of one color channel : from + ( to - from ) x step / 32
//   ( >>> 5 is a division by 32 that keeps the minus sign , the result can go down too )
function automatic int blendChannel (input int from, input int to, input logic [4:0] step);
	return from + (((to - from) * int'(step)) >>> 5) ;
endfunction

// the blend of a 3-3-2 color : every channel ( red , green , blue ) on its own
function automatic logic [7:0] blend (input logic [7:0] from, input logic [7:0] to, input logic [4:0] step);
	logic [2:0] r , g ;
	logic [1:0] b ;
	r = 3'(blendChannel(int'(from[7:5]), int'(to[7:5]), step)) ;
	g = 3'(blendChannel(int'(from[4:2]), int'(to[4:2]), step)) ;
	b = 2'(blendChannel(int'(from[1:0]), int'(to[1:0]), step)) ;
	return {r, g, b} ;
endfunction

//////////--------------------------------------------------------------------------------------------------------------=
// stage 1 register : the pixel in every layer , and the colors of this moment
logic [9:0] starX_d ;        // X in the stars layer ( far )
logic [8:0] y_d ;
logic [7:0] cloudAX_d ;      // X in the first line of clouds ( a cloud every 256 pixels )
logic [7:0] cloudBX_d ;      // X in the second line of clouds ( moved by half : 128 pixels )
logic [8:0] skylineX_d ;     // X in the skyline ( it repeats every 512 pixels )
logic [7:0] skyTop_d , skyBottom_d , cloud_d , building_d , window_d ;   // the blended colors
logic       night_d ;
logic       onScreen_d ;     // outside the 640x480 screen the output is black

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		starX_d     <= '0 ;
		y_d         <= '0 ;
		cloudAX_d   <= '0 ;
		cloudBX_d   <= '0 ;
		skylineX_d  <= '0 ;
		skyTop_d    <= SKY_TOP_KEY[0] ;
		skyBottom_d <= SKY_BOTTOM_KEY[0] ;
		cloud_d     <= CLOUD_KEY[0] ;
		building_d  <= BUILDING_KEY[0] ;
		window_d    <= WINDOW_KEY[0] ;
		night_d     <= 1'b0 ;
		onScreen_d  <= 1'b0 ;
	end
	else begin
		starX_d     <= 10'(pixelX) + farOffset ;
		y_d         <= 9'(pixelY) ;
		cloudAX_d   <= 8'(pixelX) + nearOffset ;
		cloudBX_d   <= 8'(pixelX) + nearOffset + 8'd128 ;
		skylineX_d  <= 9'(pixelX) + midOffset ;
		skyTop_d    <= blend(SKY_TOP_KEY[fromScene],    SKY_TOP_KEY[toScene],    blendStep) ;
		skyBottom_d <= blend(SKY_BOTTOM_KEY[fromScene], SKY_BOTTOM_KEY[toScene], blendStep) ;
		cloud_d     <= blend(CLOUD_KEY[fromScene],      CLOUD_KEY[toScene],      blendStep) ;
		building_d  <= blend(BUILDING_KEY[fromScene],   BUILDING_KEY[toScene],   blendStep) ;
		window_d    <= blend(WINDOW_KEY[fromScene],     WINDOW_KEY[toScene],     blendStep) ;
		night_d     <= isNight ;
		onScreen_d  <= (pixelX >= 0) && (pixelX < 640) && (pixelY >= 0) && (pixelY < 480) ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// stage 2 : what is at this pixel ?

// clouds : two lines of clouds , every cloud is 64x32 ( the 32x16 bitmap drawn twice as big )
logic        inCloudA , inCloudB ;
logic [3:0]  cloudRowIndex ;     // the bitmap row ( screen row / 2 )
logic [4:0]  cloudColIndex ;     // the bitmap column ( screen column / 2 )
logic [31:0] cloudRow ;
logic        isCloud ;

assign inCloudA      = (cloudAX_d < 8'd64) && (int'(y_d) >= CLOUD_A_Y) && (int'(y_d) < CLOUD_A_Y + 32) ;
assign inCloudB      = (cloudBX_d < 8'd64) && (int'(y_d) >= CLOUD_B_Y) && (int'(y_d) < CLOUD_B_Y + 32) ;
assign cloudRowIndex = inCloudA ? 4'((int'(y_d) - CLOUD_A_Y) / 2) : 4'((int'(y_d) - CLOUD_B_Y) / 2) ;
assign cloudColIndex = inCloudA ? cloudAX_d[5:1] : cloudBX_d[5:1] ;      // [5:1] = the column 0..63 divided by 2
assign cloudRow      = CLOUD_BITMAP[cloudRowIndex] ;
assign isCloud       = (inCloudA || inCloudB) && cloudRow[5'd31 - cloudColIndex] ;   // bit 31 is the left pixel

// skyline : 16 buildings , each 32 pixels wide , with the heights of the table
logic [3:0] buildingIndex ;      // which building ( skyline X / 32 )
logic [4:0] xInBuilding ;        // the column inside the building , 0..31
int         roofY ;              // the top row of the building
logic       isBuilding , isWindow , windowLit ;

assign buildingIndex = skylineX_d[8:5] ;
assign xInBuilding   = skylineX_d[4:0] ;
assign roofY         = SCREEN_BOTTOM - int'(BUILDING_HEIGHT[buildingIndex]) ;
assign isBuilding    = (int'(y_d) >= roofY) ;
// the windows : 4 pixels wide every 8 columns , 6 rows high every 16 rows , not at the sides and not under the roof
assign isWindow      = isBuilding
                       && (xInBuilding >= 5'd4) && (xInBuilding < 5'd28)
                       && (xInBuilding[2:0] >= 3'd2) && (xInBuilding[2:0] <= 3'd5)
                       && (y_d[3:0] >= 4'd4) && (y_d[3:0] <= 4'd9)
                       && (int'(y_d) >= roofY + 8) ;
// at night only some windows are lit ( a fixed pattern made from the position bits ) , in the day all are drawn
assign windowLit     = night_d ? (skylineX_d[3] ^ y_d[4] ^ skylineX_d[5]) : 1'b1 ;

// stars : the sky is cut into 16x16 tiles . a tile has a star in 1 of 4 cases , at a place inside the tile -
// both chosen by a "hash" ( a mix of the tile number bits with XOR ) , so the stars look random but never move
logic [9:0] starHash ;
logic       isStar ;
assign starHash = {starX_d[9:4], y_d[7:4]} ^ {y_d[6:4], starX_d[9:4], y_d[8]} ;
assign isStar   = night_d && (int'(y_d) < STARS_MAX_Y)
                  && (starHash[9:8] == 2'b00)                                  // 1 tile of 4 has a star
                  && (starX_d[3:0] == starHash[3:0]) && (y_d[3:0] == starHash[7:4]) ;   // the star pixel in the tile

// stage 2 register : the layers by priority , from the front to the back
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		backGroundRGB <= 8'h00 ;
	else begin
		if (!onScreen_d)
			backGroundRGB <= 8'h00 ;                         // outside the screen : black
		else if (isWindow && windowLit)
			backGroundRGB <= night_d ? WINDOW_LIT : window_d ;
		else if (isBuilding)
			backGroundRGB <= building_d ;
		else if (isCloud)
			backGroundRGB <= cloud_d ;
		else if (isStar)
			backGroundRGB <= 8'hFE ;                         // white ( 8'hFF means transparent )
		else if (int'(y_d) < SKY_SPLIT_Y)
			backGroundRGB <= skyTop_d ;
		else
			backGroundRGB <= skyBottom_d ;
	end
end

endmodule