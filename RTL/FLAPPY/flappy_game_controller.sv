// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_game_controller - the SAME module written in a more basic way ( the same inputs , outputs and results )
//
//   the differences from the project version :
//     * every register ( or small group of registers ) has its own always_ff block , with its own simple rules
//     * the points of this clock ( 0 , 1 , 2 or 3 ) come from a simple if / else list
//     * the new score is ONE addition on paper : add the points to the ones digit , then carry 1 to the next digit
//     * two helper signals give a name to the two big events : startGame and gameEnds
//
//   states     : START --ENTER--> PLAY --hit--> GAME_OVER --ENTER--> PLAY ...
//   score      : +1 for a passed pipe , +2 for a coin . kept in BCD ( one decimal digit in every 4 bits ) , max 9999
//   level      : the tens digit of the score ( 0..7 )
//   timers     : they count FRAMES ( 73 frames = 1 second ) . an event is "on" while its timer is not 0

module flappy_game_controller (
	input  logic clk,
	input  logic resetN,
	input  logic startOfFrame,       // a pulse at the start of every frame
	input  logic startKey,           // ENTER ( 1 while pressed )
	input  logic hitPulse,           // the bird hit a pipe or the border
	input  logic scorePulse,         // the bird passed a pipe : +1
	input  logic coinPulse,          // the bird took a coin : +2
	input  logic shieldPulse,        // the bird took a shield
	input  logic shatterPulse,       // the shielded bird broke a pipe : the shield is used
	input  logic hourglassPulse,     // the bird took an hourglass
	input  logic confusePulse,       // the bird touched a purple trap
	input  logic cheatNoDeath,       // switch : hits do not kill

	output logic [1:0]  gameState,      // 0 START , 1 PLAY , 2 GAME_OVER
	output logic        playEnable,     // 1 while playing
	output logic        newGamePulse,   // one clock when a new game starts
	output logic [15:0] scoreBCD,       // 4 BCD digits
	output logic [15:0] highScoreBCD,   // 4 BCD digits , the best score
	output logic [2:0]  level,          // 0..7
	output logic        shieldActive,   // the shield is on
	output logic        slowMoActive,   // slow motion is on
	output logic        invertControls, // the keys are swapped
	output logic        nightMode,      // night mode is on
	output logic [8:0]  dayStep,        // the position of the sun / moon on its path ( 0..511 )
	output logic        pipesVisible,   // 0 : the pipes are hidden now ( the invisible maze )
	output logic [3:0]  msgId           // the message on the screen ( 0 = no message )
);

//////////--------------------------------------------------------------------------------------------------------------=
// 1. constants ( 73 frames = 1 second )
localparam logic [1:0] STATE_START     = 2'd0 ;
localparam logic [1:0] STATE_PLAY      = 2'd1 ;
localparam logic [1:0] STATE_GAME_OVER = 2'd2 ;

localparam logic [9:0]  SHIELD_FRAMES    = 10'd730 ;   // 10 seconds
localparam logic [9:0]  SLOW_FRAMES      = 10'd730 ;   // 10 seconds
localparam logic [9:0]  CONFUSE_FRAMES   = 10'd511 ;   //  7 seconds
localparam logic [8:0]  NIGHT_FRAMES     = 9'd365 ;    //  5 seconds
localparam logic [4:0]  NIGHT_EVERY      = 5'd15 ;     // night mode every 15 points
localparam logic [5:0]  GAME_OVER_FRAMES = 6'd60 ;     // wait 0.8 second before a new game is allowed
localparam logic [10:0] BLINK_PERIOD     = 11'd1825 ;  // the invisible maze : every 25 seconds ...
localparam logic [10:0] BLINK_VISIBLE    = 11'd1752 ;  // ... 24 seconds visible , then 1 second hidden
localparam logic [7:0]  MSG_FRAMES       = 8'd146 ;    // a message stays 2 seconds

localparam logic [2:0] BLINK_LEVEL     = 3'd3 ;   // the invisible maze from level 3
localparam logic [2:0] CLOSE_LEVEL     = 3'd4 ;   // the crushing pipes from level 4
localparam logic [2:0] MAX_SPEED_LEVEL = 3'd4 ;   // the pipes get faster up to level 4

// the messages ( their texts are in flappy_text_draw )
localparam logic [3:0] MSG_NONE      = 4'd0 ;
localparam logic [3:0] MSG_GO        = 4'd1 ;
localparam logic [3:0] MSG_FASTER    = 4'd2 ;
localparam logic [3:0] MSG_INVISIBLE = 4'd3 ;
localparam logic [3:0] MSG_CLOSING   = 4'd4 ;
localparam logic [3:0] MSG_LEVEL     = 4'd5 ;
localparam logic [3:0] MSG_NIGHT     = 4'd6 ;
localparam logic [3:0] MSG_SHIELD    = 4'd7 ;
localparam logic [3:0] MSG_SLOW      = 4'd8 ;
localparam logic [3:0] MSG_REVERSED  = 4'd9 ;
localparam logic [3:0] MSG_BROKEN    = 4'd10 ;

//////////--------------------------------------------------------------------------------------------------------------=
// 2. the registers
logic        startKey_d ;       // ENTER one clock ago
logic [9:0]  shieldFrames ;     // frames left of the shield
logic [9:0]  slowFrames ;       // frames left of the slow motion
logic [9:0]  confuseFrames ;    // frames left of the swapped keys
logic [8:0]  nightFrames ;      // frames left of the night mode
logic [4:0]  nightPoints ;      // points since the last night mode ( 0..14 )
logic [5:0]  gameOverFrames ;   // frames since GAME_OVER ( stops at 60 )
logic [10:0] blinkFrames ;      // the invisible maze : frame 0..1824 of the 25 second period
logic [11:0] dayCycle ;         // frames played ( not counted in GAME_OVER )

//////////--------------------------------------------------------------------------------------------------------------=
// 3. simple signals ( wires )
logic       startPressed ;      // ENTER is pressed now ( 1 now , 0 one clock ago )
logic       lethal ;            // a hit that kills
logic       waiting ;           // we are on the START or the GAME_OVER screen
logic       startGame ;         // a new game starts in this clock
logic       gameEnds ;          // the game ends in this clock
logic       playing ;           // we play and the game does not end in this clock
logic [1:0] addPoints ;         // points of this clock : 0 , 1 , 2 or 3
logic       nightStart ;        // the night mode starts in this clock

assign startPressed = startKey && !startKey_d ;
assign lethal       = hitPulse && !cheatNoDeath ;
assign waiting      = (gameState == STATE_START) || (gameState == STATE_GAME_OVER) ;
assign startGame    = waiting && startPressed && ((gameState == STATE_START) || (gameOverFrames >= GAME_OVER_FRAMES)) ;
assign gameEnds     = (gameState == STATE_PLAY) && lethal ;
assign playing      = (gameState == STATE_PLAY) && !lethal ;

// the points of this clock
always_comb
begin
	if (scorePulse && coinPulse)
		addPoints = 2'd3 ;             // a pipe and a coin together
	else if (coinPulse)
		addPoints = 2'd2 ;             // a coin
	else if (scorePulse)
		addPoints = 2'd1 ;             // a pipe
	else
		addPoints = 2'd0 ;
end

assign nightStart     = (addPoints != 2'd0) && ({3'b0, addPoints} + nightPoints >= NIGHT_EVERY) ;

assign playEnable     = (gameState == STATE_PLAY) ;
assign shieldActive   = (shieldFrames  != 10'd0) ;      // "on" = the timer is not 0
assign slowMoActive   = (slowFrames    != 10'd0) ;
assign invertControls = (confuseFrames != 10'd0) ;
assign nightMode      = (nightFrames   != 9'd0) ;
assign dayStep        = dayCycle[11:3] ;                // dayCycle / 8
assign pipesVisible   = (gameState != STATE_PLAY) || (level < BLINK_LEVEL) || (blinkFrames < BLINK_VISIBLE) ;

//////////--------------------------------------------------------------------------------------------------------------=
// 4. the new score : score + points , in BCD , like an addition on paper
//    add the points to the ones digit ; a digit of 10 or more gives "-10" and a carry of 1 to the next digit
//    if the thousands digit overflows the score stays 9999
logic [4:0]  ones , tens , hundreds , thousands ;      // 5 bits : a digit plus a carry can reach 12
logic [15:0] newScore ;
logic [2:0]  newLevel ;

always_comb
begin
	ones      = {1'b0, scoreBCD[3:0]}   + {3'b0, addPoints} ;
	tens      = {1'b0, scoreBCD[7:4]} ;
	hundreds  = {1'b0, scoreBCD[11:8]} ;
	thousands = {1'b0, scoreBCD[15:12]} ;

	if (ones >= 5'd10)      begin ones      = ones      - 5'd10 ; tens      = tens      + 5'd1 ; end
	if (tens >= 5'd10)      begin tens      = tens      - 5'd10 ; hundreds  = hundreds  + 5'd1 ; end
	if (hundreds >= 5'd10)  begin hundreds  = hundreds  - 5'd10 ; thousands = thousands + 5'd1 ; end

	if (thousands >= 5'd10)
		newScore = 16'h9999 ;                                     // the maximum score
	else
		newScore = {thousands[3:0], hundreds[3:0], tens[3:0], ones[3:0]} ;

	// the level = the tens digit ( 0..6 ) , or 7 from score 70
	if ((newScore[15:8] != 8'h00) || (newScore[7:4] >= 4'd7))
		newLevel = 3'd7 ;
	else
		newLevel = newScore[6:4] ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 5. the state machine
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		gameState <= STATE_START ;
	else if (startGame)
		gameState <= STATE_PLAY ;
	else if (gameEnds)
		gameState <= STATE_GAME_OVER ;
	else if (gameState == 2'd3)
		gameState <= STATE_START ;                 // a wrong state ( it can not happen ) : back to START
end

// ENTER one clock ago , and the one-clock pulse of a new game
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		startKey_d   <= 1'b0 ;
		newGamePulse <= 1'b0 ;
	end
	else begin
		startKey_d   <= startKey ;
		newGamePulse <= startGame ;                // 1 for exactly one clock
	end
end

// the frames on the START / GAME_OVER screen ( stop at 60 )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		gameOverFrames <= 6'd0 ;
	else if (gameEnds)
		gameOverFrames <= 6'd0 ;
	else if (waiting && startOfFrame && (gameOverFrames < GAME_OVER_FRAMES))
		gameOverFrames <= gameOverFrames + 6'd1 ;
end

// the sun / moon counter : every frame , except on the GAME OVER screen
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		dayCycle <= 12'd0 ;
	else if (startOfFrame && (gameState != STATE_GAME_OVER))
		dayCycle <= dayCycle + 12'd1 ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 6. the score , the level and the best score
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		scoreBCD <= 16'h0 ;
		level    <= 3'd0 ;
	end
	else if (startGame) begin
		scoreBCD <= 16'h0 ;
		level    <= 3'd0 ;
	end
	else if (playing && (addPoints != 2'd0)) begin
		scoreBCD <= newScore ;
		level    <= newLevel ;
	end
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		highScoreBCD <= 16'h0 ;
	else if (gameEnds && (scoreBCD > highScoreBCD))     // BCD numbers compare like normal binary numbers
		highScoreBCD <= scoreBCD ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 7. the night mode : a points counter ( 0..14 ) and a 5 second timer
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		nightPoints <= 5'd0 ;
	else if (startGame)
		nightPoints <= 5'd0 ;
	else if (playing && (addPoints != 2'd0)) begin
		if (nightStart)
			nightPoints <= nightPoints + {3'b0, addPoints} - NIGHT_EVERY ;   // keep the extra point of a coin
		else
			nightPoints <= nightPoints + {3'b0, addPoints} ;
	end
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		nightFrames <= 9'd0 ;
	else if (startGame || gameEnds)
		nightFrames <= 9'd0 ;
	else if (playing && nightStart)
		nightFrames <= NIGHT_FRAMES ;
	else if (playing && startOfFrame && nightMode)
		nightFrames <= nightFrames - 9'd1 ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 8. the item timers : load the full time on the event , then count down every frame
//    outside the game ( START / GAME_OVER ) and when the game ends they are 0
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		shieldFrames <= 10'd0 ;
	else if (waiting || gameEnds)
		shieldFrames <= 10'd0 ;
	else if (playing && shatterPulse)
		shieldFrames <= 10'd0 ;                          // a broken pipe uses the shield at once
	else if (playing && shieldPulse)
		shieldFrames <= SHIELD_FRAMES ;
	else if (playing && startOfFrame && shieldActive)
		shieldFrames <= shieldFrames - 10'd1 ;
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		slowFrames <= 10'd0 ;
	else if (waiting || gameEnds)
		slowFrames <= 10'd0 ;
	else if (playing && hourglassPulse)
		slowFrames <= SLOW_FRAMES ;
	else if (playing && startOfFrame && slowMoActive)
		slowFrames <= slowFrames - 10'd1 ;
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		confuseFrames <= 10'd0 ;
	else if (waiting || gameEnds)
		confuseFrames <= 10'd0 ;
	else if (playing && confusePulse)
		confuseFrames <= CONFUSE_FRAMES ;
	else if (playing && startOfFrame && invertControls)
		confuseFrames <= confuseFrames - 10'd1 ;
end

//////////--------------------------------------------------------------------------------------------------------------=
// 9. the invisible maze : the frames of the 25 second period ( only from level 3 )
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		blinkFrames <= 11'd0 ;
	else if (startGame)
		blinkFrames <= 11'd0 ;
	else if (playing && (level < BLINK_LEVEL))
		blinkFrames <= 11'd0 ;
	else if (playing && startOfFrame) begin
		if (blinkFrames == BLINK_PERIOD - 11'd1)
			blinkFrames <= 11'd0 ;
		else
			blinkFrames <= blinkFrames + 11'd1 ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// 10. the messages ( the same as the project version )
logic [3:0] levelMsg ;          // the message of a level up
logic [3:0] newMsg ;            // the event of this clock
logic [3:0] secondMsg ;         // a second event in the same clock
logic       levelUp ;           // the level goes up in this clock
logic [7:0] msgFrames ;         // frames left of the message
logic [3:0] msgPending ;        // the message that waits

assign levelUp = playing && (addPoints != 2'd0) && (newLevel != level) ;

always_comb
begin
	if (newLevel == BLINK_LEVEL)
		levelMsg = MSG_INVISIBLE ;
	else if (newLevel == CLOSE_LEVEL)
		levelMsg = MSG_CLOSING ;
	else if (newLevel <= MAX_SPEED_LEVEL)
		levelMsg = MSG_FASTER ;
	else
		levelMsg = MSG_LEVEL ;

	newMsg    = MSG_NONE ;
	secondMsg = MSG_NONE ;
	if (newGamePulse)
		newMsg = MSG_GO ;
	else if (playing) begin
		if (levelUp) begin
			newMsg = levelMsg ;
			if (nightStart)
				secondMsg = MSG_NIGHT ;
		end
		else if (nightStart)     newMsg = MSG_NIGHT ;
		else if (shatterPulse)   newMsg = MSG_BROKEN ;
		else if (shieldPulse)    newMsg = MSG_SHIELD ;
		else if (hourglassPulse) newMsg = MSG_SLOW ;
		else if (confusePulse)   newMsg = MSG_REVERSED ;
	end
end

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		msgId      <= MSG_NONE ;
		msgFrames  <= 8'd0 ;
		msgPending <= MSG_NONE ;
	end
	else if (newMsg != MSG_NONE) begin                      // a new event : show its message now
		msgId      <= newMsg ;
		msgFrames  <= MSG_FRAMES ;
		msgPending <= secondMsg ;
	end
	else if (!playing) begin                                 // no messages outside the game
		msgId      <= MSG_NONE ;
		msgFrames  <= 8'd0 ;
		msgPending <= MSG_NONE ;
	end
	else if (startOfFrame && (msgFrames != 8'd0)) begin     // count down the 2 seconds
		if (msgFrames == 8'd1) begin                        // the message is over : show the waiting one
			msgId      <= msgPending ;
			msgFrames  <= (msgPending != MSG_NONE) ? MSG_FRAMES : 8'd0 ;
			msgPending <= MSG_NONE ;
		end
		else
			msgFrames <= msgFrames - 8'd1 ;
	end
end

endmodule
