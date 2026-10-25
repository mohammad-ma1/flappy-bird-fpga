// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// pipes_controller : the maze - 6 pipes that scroll to the left ( "Active Pipe Control" )
//
//   * every frame all the pipes move left by the same step ( the speed grows with the level )
//   * the player moves only the ACTIVE pipe ( the first pipe in front of the bird ) up / down with the keys
//   * when the bird passes the active pipe : +1 point ( scorePulse ) and the next pipe becomes the active pipe
//   * a pipe that leaves the screen on the left is placed again on the right , behind the last pipe ,
//     with new random values : gap position , gap height , extra distance , edge coin and item
//   * a pipe never moves up or down by itself - only the active pipe , only with the keys
//   * from level 4 the two tubes of every pipe on the screen slowly close in ( the crushing pipes ) ,
//     1 pixel every 16 frames , but the gap never gets smaller than 64 pixels
//
//   the 6 pipes are a RING : pipe i+1 is always the pipe to the right of pipe i ( after pipe 5 comes pipe 0 ) ,
//   so the active pipe is only an index 0..5 that goes +1 after every pass
//
//   how the code is written : every register ( or array of 6 registers ) has its own always_ff block ,
//   and the conditions have names : newGame , moveNow ( once per frame while playing ) , leaving[i] ( pipe i leaves now )

module	pipes_controller	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	startOfFrame,          // the game tick : the pipes move once per frame
	input	logic	playEnable,            // 1 while playing ( the pipes are frozen when 0 )
	input	logic	newGamePulse,          // place the pipes for a new game
	input	logic	[2:0] level,           // 0..7 ( score / 10 )
	input	logic	turbo,                 // switch : double speed
	input	logic	keyUp,                 // numpad 8 : move the active pipe up   ( 1 while pressed )
	input	logic	keyDown,               // numpad 2 : move the active pipe down
	input	logic	invertControls,        // the purple trap : up and down are swapped
	input	logic	signed [10:0] birdX,   // left edge of the bird
	input	logic	coinPulse,             // the bird took a coin
	input	logic	shieldPulse,           // the bird took a shield
	input	logic	hourglassPulse,        // the bird took an hourglass
	input	logic	confusePulse,          // the bird touched a purple trap
	input	logic	shatterPulse,          // the shielded bird hit the active pipe : it breaks

	output	logic	signed [11:0] pipeX     [0:5],   // left edge of every pipe ( can be < 0 or > 639 : off the screen )
	output	logic	       [8:0]  gapTop    [0:5],   // the upper tube ends just above this row
	output	logic	       [8:0]  gapBottom [0:5],   // the lower tube starts at this row
	output	logic	              broken    [0:5],   // the shield broke this pipe : it is not drawn and does not kill
	output	logic	       [1:0]  edgeCoin  [0:5],   // 0 no coin , 1 coin at the top of the gap , 2 coin at the bottom
	output	logic	              itemOn    [0:5],   // the pipe has an item in front of it
	output	logic	       [1:0]  itemKind  [0:5],   // 0 coin , 1 shield , 2 hourglass , 3 purple trap
	output	logic	signed [11:0] itemX     [0:5],   // left edge of the item ( the item is 16x16 )
	output	logic	       [8:0]  itemY     [0:5],   // top row of the item
	output	logic	[2:0] activeIndex,               // the pipe the player controls
	output	logic	scorePulse                       // one clock : the bird passed the active pipe
);

//////////--------------------------------------------------------------------------------------------------------------=
// 1. numbers of the game ( tune here )
parameter int NUM_PIPES       = 6;
parameter int PIPE_WIDTH      = 48;    // pixels ( the same value is in pipes_draw )
parameter int FIRST_PIPE_X    = 512;   // a new game : pipe 0 starts here , the next pipes every SPACING_BASE pixels
parameter int START_GAP       = 128;   // gap height of the pipes of a new game
parameter int GAP_MIN         = 112;   // a new pipe : gap height = 112 + random 0..31
parameter int GAP_TOP_MIN     = 48;    // a new pipe : gap top    =  48 + random 0..255
parameter int GAP_LIMIT_TOP   = 16;    // the player can move a gap only between these rows
parameter int GAP_LIMIT_BOT   = 464;
parameter int SPACING_BASE    = 224;   // distance between two pipes at level 0 ...
parameter int SPACING_STEP    = 16;    // ... 16 pixels less every level ( 160 from level 4 ) , + random 0..62
parameter int MAX_SPEED_LEVEL = 4;     // the speed and the distance stop changing at this level
parameter int KEY_SPEED       = 6;     // pixels per frame the keys move the active pipe at level 0 ...
parameter int KEY_SPEED_STEP  = 2;     // ... 2 more every level ( 14 from level 4 )
parameter int CLOSE_LEVEL     = 4;     // the crushing pipes start at this level ( score 40 )
parameter int CLOSE_FRAMES    = 16;    // the tubes close in 1 pixel every 16 frames
parameter int MIN_SAFE_GAP    = 64;    // the gap never gets smaller than this ( the 32 pixel bird + 16 above and below )
parameter int CONFUSE_LEVEL   = 1;     // the purple trap appears from this level

localparam logic [1:0] EDGE_NONE      = 2'd0 ;   // edge coin codes : 0 none , 1 top , 2 bottom
localparam logic [1:0] KIND_COIN      = 2'd0 ;   // item kinds
localparam logic [1:0] KIND_SHIELD    = 2'd1 ;
localparam logic [1:0] KIND_HOURGLASS = 2'd2 ;
localparam logic [1:0] KIND_TRAP      = 2'd3 ;

//////////--------------------------------------------------------------------------------------------------------------=
// 2. the registers of every pipe ( pipeX , broken , edgeCoin , itemOn , itemKind are the outputs themselves )
logic [8:0] pipeY   [0:5] ;   // top row of the gap ( the keys change it )
logic [7:0] gapH    [0:5] ;   // height of the gap ( random , chosen when the pipe is placed )
logic [5:0] squeeze [0:5] ;   // the crushing pipes : how many pixels each tube has moved toward the middle
logic [5:0] itemDX  [0:5] ;   // the item is 24 + itemDX pixels to the left of the pipe ( 0..63 )
logic [6:0] itemDY  [0:5] ;   // the item is itemDY pixels below the gap top ( 8..86 , always inside the gap )

//////////--------------------------------------------------------------------------------------------------------------=
// 3. the two big conditions of this clock
logic newGame ;     // place the pipes of a new game
logic moveNow ;     // once per frame , while playing : the pipes move
assign newGame = newGamePulse ;
assign moveNow = startOfFrame && playEnable && !newGamePulse ;

//////////--------------------------------------------------------------------------------------------------------------=
// 4. random numbers : a 16 bit LFSR ( linear feedback shift register )
//   one step : shift left by 1 , the new bit 0 is bit15 XOR bit13 XOR bit12 XOR bit10
//   it goes through all the 65535 non zero values in a fixed order that looks random ( only XOR gates )
function automatic logic [15:0] lfsrNext (input logic [15:0] v);
	return {v[14:0], v[15] ^ v[13] ^ v[12] ^ v[10]} ;
endfunction

// 8 steps at once ( the same XOR circuit 8 times , one after the other )
function automatic logic [15:0] lfsrNext8 (input logic [15:0] v);
	for (int k = 0; k < 8; k++)
		v = lfsrNext(v) ;
	return v ;
endfunction

logic [15:0] lfsr ;         // runs every clock : its value when ENTER is pressed is the seed of a new game
logic [15:0] pipeRandom ;   // the random generator of the new pipes : it moves 24 steps for every new pipe

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		lfsr <= 16'h1D2B ;          // any value but 0
	else
		lfsr <= lfsrNext(lfsr) ;
end

// three random words for the next new pipe ( 48 random bits ) : rand1 , then 8 steps later , then 8 more
logic [15:0] rand1 , rand2 , rand3 ;
assign rand1 = pipeRandom ;
assign rand2 = lfsrNext8(rand1) ;
assign rand3 = lfsrNext8(rand2) ;

//////////--------------------------------------------------------------------------------------------------------------=
// 5. the random values of a new pipe
logic [8:0]  newGapTop ;     // 48..303
logic [7:0]  newGapH ;       // 112..143
logic [5:0]  newExtraX ;     // 0..62 ( even ) : extra distance to the pipe before it
logic [1:0]  newEdgeCoin ;   // none , top or bottom
logic        newItemOn ;     // 3 of 4 new pipes get an item
logic [1:0]  newItemKind ;
logic [5:0]  newItemDX ;     // 0..63
logic [6:0]  newItemDY ;     // 8..86

always_comb
begin
	newGapTop = 9'(GAP_TOP_MIN) + {1'b0, rand1[7:0]} ;                  // 48 + ( 0..255 )
	newGapH   = 8'(GAP_MIN) + {3'b0, rand2[4:0]} ;                      // 112 + ( 0..31 )
	newExtraX = {rand3[8:4], 1'b0} ;                                    // 2 x ( 0..31 ) : an even number
	newItemDX = rand3[15:10] ;                                          // 0..63
	newItemDY = 7'd8 + {1'b0, rand2[15:10]} + {3'b0, rand2[13:10]} ;    // 8 + ( 0..63 ) + ( 0..15 )

	// the edge coin : 2 random bits - 0 none , 1 top , 2 bottom , and 3 is also none
	if (rand1[10:9] == 2'd3)
		newEdgeCoin = EDGE_NONE ;
	else
		newEdgeCoin = rand1[10:9] ;

	// an item : 2 random bits , 3 of the 4 values give an item
	newItemOn = (rand1[12:11] != 2'd0) ;

	// the item kind : 4 random bits . each special value comes 1 time in 16 , all the others are a coin
	if (rand3[3:0] == 4'd0)
		newItemKind = KIND_SHIELD ;
	else if (rand3[3:0] == 4'd15)
		newItemKind = KIND_HOURGLASS ;
	else if ((rand3[3:0] == 4'd8) && (level >= 3'(CONFUSE_LEVEL)))
		newItemKind = KIND_TRAP ;
	else
		newItemKind = KIND_COIN ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 6. speed and distance of this level
//   the pipes move ( 4 + level ) QUARTER pixels per frame : 1 , 1.25 , 1.5 , 1.75 , 2 pixels ( x2 with turbo )
//   distance counts the quarter pixels ; the whole pixels that it passes in this frame are the step of this frame
//   ( example : speed 1.25 gives the steps 1 , 1 , 1 , 2 , 1 , 1 , 1 , 2 ... )
logic [2:0]  speedLevel ;      // the level , but not above MAX_SPEED_LEVEL
logic [4:0]  speed ;           // quarter pixels per frame
logic [11:0] distance ;        // total distance in quarter pixels ( it wraps around - that is fine )
logic [11:0] distanceNext ;
logic [9:0]  step ;            // whole pixels to move in this frame
int          spacing ;         // distance between two pipes
int          keySpeed ;        // pixels per frame of the keys

always_comb
begin
	if (level > 3'(MAX_SPEED_LEVEL))
		speedLevel = 3'(MAX_SPEED_LEVEL) ;
	else
		speedLevel = level ;

	speed = 5'(4 + int'(speedLevel)) ;            // 4 , 5 , 6 , 7 , 8 quarter pixels
	if (turbo)
		speed = 5'(2 * int'(speed)) ;             // turbo : twice as fast

	distanceNext = distance + 12'(speed) ;
	step         = distanceNext[11:2] - distance[11:2] ;   // [11:2] = distance / 4 = whole pixels
	spacing      = SPACING_BASE - SPACING_STEP * int'(speedLevel) ;
	keySpeed     = KEY_SPEED + KEY_SPEED_STEP * int'(speedLevel) ;
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		distance <= 12'd0 ;
	else if (newGame)
		distance <= 12'd0 ;
	else if (moveNow)
		distance <= distanceNext ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 7. the crushing pipes : a slow counter 0..15 , one closing step when it is at 15 ( every 16 frames )
logic [3:0] closeCount ;
logic       closeTick ;
assign closeTick = (closeCount == 4'(CLOSE_FRAMES - 1)) && (level >= 3'(CLOSE_LEVEL)) ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		closeCount <= 4'd0 ;
	else if (moveNow)
		closeCount <= closeCount + 4'd1 ;          // 0..15 , then 0 again
end

//////////--------------------------------------------------------------------------------------------------------------=
// 8. which pipe leaves the screen in this frame , and where it is placed again
logic        leaving   [0:5] ;   // pipe i leaves the screen now ( its right edge passes x = 0 )
logic [11:0] recycledX [0:5] ;   // its new place : behind the pipe before it in the ring ( the last pipe )
logic [11:0] scrolledX [0:5] ;   // or : the same pipe , step pixels to the left

always_comb
begin
	for (int i = 0; i < NUM_PIPES; i++) begin
		leaving[i]   = (int'(pipeX[i]) - int'(step) + PIPE_WIDTH <= 0) ;
		recycledX[i] = 12'(int'(pipeX[(i == 0) ? NUM_PIPES - 1 : i - 1]) - int'(step) + spacing + int'(newExtraX)) ;
		scrolledX[i] = 12'(int'(pipeX[i]) - int'(step)) ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// 9. the active pipe : the keys , and "did the bird pass it ?"
logic upPressed , downPressed ;   // the keys after the purple trap swap
int   move ;                      // pixels the keys move the active pipe in this frame ( negative = up )
int   wantedY ;                   // the new gap top of the active pipe
logic [8:0] newActiveY ;
logic activePassed ;              // the right edge of the active pipe is left of the bird
logic [2:0] nextIndex ;           // the next pipe in the ring

always_comb
begin
	// the purple trap swaps the two keys
	if (invertControls) begin
		upPressed   = keyDown ;
		downPressed = keyUp ;
	end
	else begin
		upPressed   = keyUp ;
		downPressed = keyDown ;
	end

	move = 0 ;
	if (upPressed && !downPressed)
		move = -keySpeed ;
	if (downPressed && !upPressed)
		move = keySpeed ;

	// the new gap top , kept between the screen limits ( the whole gap stays on the screen )
	wantedY = int'(pipeY[activeIndex]) + move ;
	if (wantedY < GAP_LIMIT_TOP)
		wantedY = GAP_LIMIT_TOP ;
	if (wantedY > GAP_LIMIT_BOT - int'(gapH[activeIndex]))
		wantedY = GAP_LIMIT_BOT - int'(gapH[activeIndex]) ;
	newActiveY = 9'(wantedY) ;

	// passed : the right edge of the active pipe is left of the bird
	activePassed = (int'(pipeX[activeIndex]) + PIPE_WIDTH < int'(birdX)) ;

	// after pipe 5 comes pipe 0
	if (activeIndex == 3'(NUM_PIPES - 1))
		nextIndex = 3'd0 ;
	else
		nextIndex = activeIndex + 3'd1 ;
end

// the active pipe and the point
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		activeIndex <= 3'd0 ;
	else if (newGame)
		activeIndex <= 3'd0 ;
	else if (moveNow && activePassed)
		activeIndex <= nextIndex ;
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		scorePulse <= 1'b0 ;
	else
		scorePulse <= moveNow && activePassed ;       // 1 for exactly one clock
end

//////////--------------------------------------------------------------------------------------------------------------=
// 10. what the bird takes from the active pipe
//   itemAtBird : the item of the active pipe touches the bird ( so a coin pulse is for the item and not for the edge coin )
logic itemAtBird ;
logic takeItem ;        // the item of the active pipe disappears now
logic takeEdgeCoin ;    // the edge coin of the active pipe disappears now

always_comb
begin
	itemAtBird = itemOn[activeIndex]
	             && (int'(itemX[activeIndex]) < int'(birdX) + 32)       // the item ( 16 wide ) and the bird ( 32 wide )
	             && (int'(itemX[activeIndex]) + 16 > int'(birdX)) ;     // overlap in X

	takeItem = 1'b0 ;
	if (itemAtBird && shieldPulse    && (itemKind[activeIndex] == KIND_SHIELD))    takeItem = 1'b1 ;
	if (itemAtBird && hourglassPulse && (itemKind[activeIndex] == KIND_HOURGLASS)) takeItem = 1'b1 ;
	if (itemAtBird && confusePulse   && (itemKind[activeIndex] == KIND_TRAP))      takeItem = 1'b1 ;
	if (itemAtBird && coinPulse      && (itemKind[activeIndex] == KIND_COIN))      takeItem = 1'b1 ;

	// a coin that is not the item coin is the edge coin
	takeEdgeCoin = coinPulse && !(itemAtBird && (itemKind[activeIndex] == KIND_COIN)) ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 11. the X of every pipe
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++)
			pipeX[i] <= 12'(FIRST_PIPE_X + i * SPACING_BASE) ;          // 512 , 736 , 960 , 1184 , 1408 , 1632
	end
	else if (newGame) begin
		for (int i = 0; i < NUM_PIPES; i++)
			pipeX[i] <= 12'(FIRST_PIPE_X + i * SPACING_BASE) ;
	end
	else if (moveNow) begin
		for (int i = 0; i < NUM_PIPES; i++) begin
			if (leaving[i])
				pipeX[i] <= recycledX[i] ;           // placed again on the right
			else
				pipeX[i] <= scrolledX[i] ;           // scroll left
		end
	end
end

// the Y of every pipe ( the top row of the gap )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++)
			pipeY[i] <= 9'(240 - START_GAP / 2) ;                       // the middle of the screen
	end
	else if (newGame) begin
		for (int i = 0; i < NUM_PIPES; i++)
			pipeY[i] <= 9'd144 + {3'b0, 6'(lfsr >> (2 * i))} ;          // 144..207 : near the middle , random
	end
	else if (moveNow) begin
		for (int i = 0; i < NUM_PIPES; i++)
			if (leaving[i])
				pipeY[i] <= newGapTop ;              // a new pipe : a new random gap - the ONLY Y change without the keys
		pipeY[activeIndex] <= newActiveY ;           // the keys move only the active pipe ( written last , so it wins )
	end
end

// the gap height and the crushing of every pipe
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++) begin
			gapH[i]    <= 8'(START_GAP) ;
			squeeze[i] <= 6'd0 ;
		end
	end
	else if (newGame) begin
		for (int i = 0; i < NUM_PIPES; i++) begin
			gapH[i]    <= 8'(START_GAP) ;
			squeeze[i] <= 6'd0 ;
		end
	end
	else if (moveNow) begin
		for (int i = 0; i < NUM_PIPES; i++) begin
			if (leaving[i]) begin
				gapH[i]    <= newGapH ;
				squeeze[i] <= 6'd0 ;                 // a new pipe starts with its gap open
			end
			// the crushing pipes : 1 pixel per tube , only on the screen , while the gap stays >= MIN_SAFE_GAP
			else if (closeTick && (pipeX[i] < 12'sd640) && (int'(gapH[i]) - 2 * int'(squeeze[i]) >= MIN_SAFE_GAP + 2))
				squeeze[i] <= squeeze[i] + 6'd1 ;
		end
	end
end

// the random generator of the new pipes
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		pipeRandom <= 16'hB400 ;
	else if (newGame)
		pipeRandom <= lfsr ;                         // the time of ENTER is random , so every game is different
	else if (moveNow) begin
		for (int i = 0; i < NUM_PIPES; i++)
			if (leaving[i])
				pipeRandom <= lfsrNext8(rand3) ;     // 24 steps : new random words for the next new pipe
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// 12. the things on every pipe : the broken flag , the edge coin and the item
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++)
			broken[i] <= 1'b0 ;
	end
	else begin
		if (newGame) begin
			for (int i = 0; i < NUM_PIPES; i++)
				broken[i] <= 1'b0 ;
		end
		else if (moveNow) begin
			for (int i = 0; i < NUM_PIPES; i++)
				if (leaving[i])
					broken[i] <= 1'b0 ;              // a new pipe is not broken
		end
		if (shatterPulse)
			broken[activeIndex] <= 1'b1 ;            // the shielded bird broke the active pipe
	end
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++)
			edgeCoin[i] <= EDGE_NONE ;
	end
	else begin
		if (newGame) begin
			for (int i = 0; i < NUM_PIPES; i++)
				if (i == 0 || 2'(lfsr >> i) == 2'd3)
					edgeCoin[i] <= EDGE_NONE ;       // no coin on the first pipe
				else
					edgeCoin[i] <= 2'(lfsr >> i) ;
		end
		else if (moveNow) begin
			for (int i = 0; i < NUM_PIPES; i++)
				if (leaving[i])
					edgeCoin[i] <= newEdgeCoin ;
		end
		if (takeEdgeCoin)
			edgeCoin[activeIndex] <= EDGE_NONE ;     // the bird took the edge coin
	end
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		for (int i = 0; i < NUM_PIPES; i++) begin
			itemOn[i]   <= 1'b0 ;
			itemKind[i] <= KIND_COIN ;
			itemDX[i]   <= 6'd0 ;
			itemDY[i]   <= 7'd0 ;
		end
	end
	else begin
		if (newGame) begin
			for (int i = 0; i < NUM_PIPES; i++) begin
				itemOn[i]   <= (i != 0) && lfsr[4 + i] ;               // no item before the first pipe
				itemKind[i] <= KIND_COIN ;                             // a new game starts with coins only
				itemDX[i]   <= 6'(lfsr >> i) ;
				itemDY[i]   <= 7'd8 + {1'b0, 6'(lfsr >> (i + 2))} ;    // 8..71
			end
		end
		else if (moveNow) begin
			for (int i = 0; i < NUM_PIPES; i++)
				if (leaving[i]) begin
					itemOn[i]   <= newItemOn ;
					itemKind[i] <= newItemKind ;
					itemDX[i]   <= newItemDX ;
					itemDY[i]   <= newItemDY ;
				end
		end
		if (takeItem)
			itemOn[activeIndex] <= 1'b0 ;            // the bird took the item
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// 13. outputs : the gap edges and the item position of every pipe
always_comb
begin
	for (int i = 0; i < NUM_PIPES; i++) begin
		gapTop[i]    = pipeY[i] + {3'b0, squeeze[i]} ;                       // the tubes close in from both sides
		gapBottom[i] = pipeY[i] + {1'b0, gapH[i]} - {3'b0, squeeze[i]} ;
		itemX[i]     = 12'(int'(pipeX[i]) - 24 - int'(itemDX[i])) ;
		itemY[i]     = pipeY[i] + {2'b0, itemDY[i]} ;
	end
end

endmodule
