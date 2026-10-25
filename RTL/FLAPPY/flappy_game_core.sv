// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// flappy_game_core : all the game modules connected together ( everything except the board parts )
// inputs : the VGA pixel and startOfFrame , keys and switches .  outputs : RGB for the VGA , score , sound control
// the board top ( TOP_FLAPPY ) connects it to the PLL , VGA_Controller , keyboard , AUDIO and 7-segment
//
//   flappy_game_controller : states , score , level , shield / slow motion / confusion timers , night mode
//   pipes_controller       : active pipe control ( the only Y movement ) , random gaps / spacing off-screen , coins ,
//                            rare items ( shield , hourglass , purple confusion trap ) , shattered pipes
//   flappy_bird_logic      : the fixed bird ( wings only )
//   parallax_layers        : the offsets of the three moving background layers
//   draw modules           : flappy_bird_draw , pipes_draw , items_draw , flappy_background , celestial_draw ,
//                            flappy_text_draw
//   flappy_collision_detector : lethal / coin / shield / shatter / hourglass / confusion , one pulse of each per frame
//   flappy_objects_mux     : priority , game over dimming , night mode ( only a circle around the bird is visible )
//   flappy_sound_control   : melodies of the course AUDIO block
//
// GAME TICK ( the enable generator of the game logic ) : the moving parts of the game ( pipes , bird wings , background and
// parallax ) update once per gameTick . normally gameTick = startOfFrame ( 72.6 updates per second ) . with the hourglass
// ( slowMoActive ) a divider lets only every 2nd startOfFrame through : the game runs at HALF speed . the timers ( level ,
// shield , slow motion , confusion ) and the collisions still use every frame , so 10 seconds stay 10 seconds

module	flappy_game_core	(
					input	logic	clk,
					input	logic	resetN,
					input 	logic signed	[10:0] pixelX,   // from VGA_Controller
					input 	logic signed	[10:0] pixelY,
					input	logic	startOfFrame,
					input	logic	startKey,       // start / restart ( ENTER )
					input	logic	keyUp,          // numpad 8 : move the active pipe up
					input	logic	keyDown,        // numpad 2 : move the active pipe down
					input	logic	cheatNoDeath,   // switch
					input	logic	turbo,          // switch

					output	logic	[7:0]  RGBOut,         // to VGA_Controller
					output	logic	[1:0]  gameState,      // 0 START , 1 PLAY , 2 GAME_OVER
					output	logic	[15:0] scoreBCD,
					output	logic	[15:0] highScoreBCD,
					output	logic	[2:0]  level,
					output	logic	shieldActive,   // ghost shield ( 10 seconds )
					output	logic	slowMoActive,   // hourglass : slow motion ( 10 seconds )
					output	logic	invertControls, // purple trap : swapped keys ( 7 seconds )
					output	logic	[3:0]  melodySelect,   // to AUDIO keyPad
					output	logic	startMelody             // to AUDIO keypadValid
);


// game state
logic        playEnable ;
logic        newGamePulse ;
logic        nightMode ;       // temporary night mode ( limited vision ) from the game controller , 5 seconds
logic [8:0]  dayStep ;         // the sun / moon position on its path ( a slow frame counter / 8 )
logic        pipesVisible ;    // the invisible maze : 0 while the pipes blink invisible
logic [3:0]  msgId ;           // the event message on the screen ( LEVEL UP , CLOSING PIPES ... )

// the game tick ( slow motion divider )
logic        slowHalf ;        // toggles every frame
logic        gameTick ;        // the moving parts of the game update now

// collisions ( collision : every lethal pixel - read by the testbench )
logic        hitPulse , scorePulse , collision ;
logic        coinPulse , shieldPulse , shatterPulse , hourglassPulse , confusePulse ;

// bird
logic signed [10:0] birdTopLeftX , birdTopLeftY ;
logic        flapFrame ;
logic        birdDrawingRequest ;
logic [7:0]  birdRGB ;

// pipes ( Active Pipe Control ) : one value per pipe , 6 pipes
logic signed [11:0] pipeX     [0:5] ;   // left edge of every pipe
logic        [8:0]  gapTop    [0:5] ;   // the upper tube ends above this row
logic        [8:0]  gapBottom [0:5] ;   // the lower tube starts at this row
logic               broken    [0:5] ;   // broken by the shield
logic        [1:0]  edgeCoin  [0:5] ;   // 0 none , 1 coin at the top of the gap , 2 at the bottom
logic               itemOn    [0:5] ;   // the item in front of the pipe
logic        [1:0]  itemKind  [0:5] ;   // 0 coin , 1 shield , 2 hourglass , 3 purple trap
logic signed [11:0] itemX     [0:5] ;
logic        [8:0]  itemY     [0:5] ;
logic [2:0]  activeIndex ;
logic        pipesDrawingRequest ;
logic [7:0]  pipesRGB ;
// items
logic        coinDrawingRequest ;
logic [7:0]  coinRGB ;
logic        shieldItemDrawingRequest ;
logic [7:0]  shieldItemRGB ;
logic        hourglassDrawingRequest ;
logic [7:0]  hourglassRGB ;
logic        confuseDrawingRequest ;
logic [7:0]  confuseRGB ;

// parallax
logic [9:0]  farOffset ;
logic [8:0]  midOffset ;
logic [7:0]  nearOffset ;

// background , sun / moon and text
logic [7:0]  backGroundRGB ;
logic        celestialDrawingRequest ;
logic [7:0]  celestialRGB ;
logic        hudDrawingRequest , overlayDrawingRequest ;
logic [7:0]  textRGB ;          // the same color for the HUD and the overlay text

//////////--------------------------------------------------------------------------------------------------------------=
// the game tick : every frame , or every 2nd frame in slow motion ( divide the game update speed by 2 )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		slowHalf <= 1'b0 ;
	else if (startOfFrame)
		slowHalf <= !slowHalf ;
end

assign gameTick = startOfFrame && (!slowMoActive || slowHalf) ;

//////////--------------------------------------------------------------------------------------------------------------=
flappy_game_controller game_controller_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(startOfFrame),
	.startKey(startKey), .hitPulse(hitPulse), .scorePulse(scorePulse),
	.coinPulse(coinPulse),
	.shieldPulse(shieldPulse), .shatterPulse(shatterPulse), .hourglassPulse(hourglassPulse), .confusePulse(confusePulse),
	.cheatNoDeath(cheatNoDeath),
	.gameState(gameState), .playEnable(playEnable), .newGamePulse(newGamePulse),
	.scoreBCD(scoreBCD), .highScoreBCD(highScoreBCD), .level(level),
	.nightMode(nightMode),
	.shieldActive(shieldActive), .slowMoActive(slowMoActive), .invertControls(invertControls),
	.dayStep(dayStep), .pipesVisible(pipesVisible), .msgId(msgId) );

flappy_bird_logic bird_logic_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(gameTick),
	.playEnable(playEnable), .newGamePulse(newGamePulse),
	.topLeftX(birdTopLeftX), .topLeftY(birdTopLeftY), .flapFrame(flapFrame) );

flappy_bird_draw bird_draw_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY),
	.topLeftX(birdTopLeftX), .topLeftY(birdTopLeftY), .flapFrame(flapFrame),
	.drawingRequest(birdDrawingRequest), .RGBout(birdRGB) );

pipes_controller pipes_controller_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(gameTick),
	.playEnable(playEnable), .newGamePulse(newGamePulse), .level(level), .turbo(turbo),
	.keyUp(keyUp), .keyDown(keyDown), .invertControls(invertControls), .birdX(birdTopLeftX),
	.coinPulse(coinPulse), .shieldPulse(shieldPulse), .hourglassPulse(hourglassPulse), .confusePulse(confusePulse),
	.shatterPulse(shatterPulse),
	.pipeX(pipeX), .gapTop(gapTop), .gapBottom(gapBottom), .broken(broken),
	.edgeCoin(edgeCoin), .itemOn(itemOn), .itemKind(itemKind), .itemX(itemX), .itemY(itemY),
	.activeIndex(activeIndex), .scorePulse(scorePulse) );

pipes_draw pipes_draw_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY),
	.pipeX(pipeX), .gapTop(gapTop), .gapBottom(gapBottom), .broken(broken), .activeIndex(activeIndex),
	.drawingRequest(pipesDrawingRequest), .RGBout(pipesRGB) );

items_draw items_draw_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY),
	.pipeX(pipeX), .gapTop(gapTop), .gapBottom(gapBottom), .broken(broken),
	.edgeCoin(edgeCoin), .itemOn(itemOn), .itemKind(itemKind), .itemX(itemX), .itemY(itemY),
	.coinDrawingRequest(coinDrawingRequest), .coinRGB(coinRGB),
	.shieldItemDrawingRequest(shieldItemDrawingRequest), .shieldItemRGB(shieldItemRGB),
	.hourglassDrawingRequest(hourglassDrawingRequest), .hourglassRGB(hourglassRGB),
	.confuseDrawingRequest(confuseDrawingRequest), .confuseRGB(confuseRGB) );
flappy_collision_detector collision_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(startOfFrame), .playEnable(playEnable),
	.pixelY(pixelY), .birdDrawingRequest(birdDrawingRequest), .pipesDrawingRequest(pipesDrawingRequest),
	.coinDrawingRequest(coinDrawingRequest),
	.shieldItemDrawingRequest(shieldItemDrawingRequest), .shieldActive(shieldActive),
	.hourglassDrawingRequest(hourglassDrawingRequest), .confuseDrawingRequest(confuseDrawingRequest),
	.collision(collision), .hitPulse(hitPulse), .coinPulse(coinPulse),
	.shieldPulse(shieldPulse), .shatterPulse(shatterPulse),
	.hourglassPulse(hourglassPulse), .confusePulse(confusePulse) );

// the parallax background layers ( frozen on the GAME OVER screen , half speed in slow motion )
parallax_layers parallax_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(gameTick), .runEnable(gameState != 2'd2),
	.farOffset(farOffset), .midOffset(midOffset), .nearOffset(nearOffset) );
flappy_background background_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY),
	.farOffset(farOffset), .midOffset(midOffset), .nearOffset(nearOffset), .startOfFrame(startOfFrame), .level(level),
	.backGroundRGB(backGroundRGB) );

// the sun and the moon of the day / night cycle
celestial_draw celestial_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .dayStep(dayStep), .level(level),
	.drawingRequest(celestialDrawingRequest), .RGBout(celestialRGB) );

flappy_text_draw text_inst (
	.clk(clk), .resetN(resetN), .startOfFrame(startOfFrame), .pixelX(pixelX), .pixelY(pixelY),
	.gameState(gameState), .scoreBCD(scoreBCD), .highScoreBCD(highScoreBCD), .level(level),
	.invertControls(invertControls), .msgId(msgId),
	.textRGB(textRGB), .hudDrawingRequest(hudDrawingRequest), .overlayDrawingRequest(overlayDrawingRequest) );

flappy_objects_mux objects_mux_inst (
	.clk(clk), .resetN(resetN), .pixelX(pixelX), .pixelY(pixelY), .gameState(gameState),
	.spotlightOn(nightMode),
	.spotCenterX(birdTopLeftX + 11'sd16), .spotCenterY(birdTopLeftY + 11'sd16),
	.textRGB(textRGB), .hudDrawingRequest(hudDrawingRequest), .overlayDrawingRequest(overlayDrawingRequest),

	.shieldItemDrawingRequest(shieldItemDrawingRequest), .shieldItemRGB(shieldItemRGB), .shieldActive(shieldActive),
	.hourglassDrawingRequest(hourglassDrawingRequest), .hourglassRGB(hourglassRGB),
	.confuseDrawingRequest(confuseDrawingRequest), .confuseRGB(confuseRGB),
	.birdDrawingRequest(birdDrawingRequest), .birdRGB(birdRGB),
	.coinDrawingRequest(coinDrawingRequest), .coinRGB(coinRGB),
	.pipesDrawingRequest(pipesDrawingRequest), .pipesRGB(pipesRGB), .pipesVisible(pipesVisible),
	.celestialDrawingRequest(celestialDrawingRequest), .celestialRGB(celestialRGB),
	.backGroundRGB(backGroundRGB),
	.RGBOut(RGBOut) );

flappy_sound_control sound_inst (
	.clk(clk), .resetN(resetN), .scorePulse(scorePulse), .hitPulse(hitPulse),
	.coinPulse(coinPulse), .shieldPulse(shieldPulse), .shatterPulse(shatterPulse),
	.hourglassPulse(hourglassPulse), .confusePulse(confusePulse), .level(level),
	.melodySelect(melodySelect), .startMelody(startMelody) );

endmodule
