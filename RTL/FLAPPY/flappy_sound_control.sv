// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_sound_control : chooses a melody of the course AUDIO block for every game event
//
//   the AUDIO block ( RTL/AUDIO , songs.mif ) plays song number keyPad when keypadValid is 1 .
//   here : keyPad = melodySelect , keypadValid = startMelody ( a 16 clock pulse )
//
//   event ( by priority )           song
//   crash                           3 "explosion"
//   the shield broke a pipe         3 "explosion"
//   purple trap                     2 "failure"
//   shield or hourglass taken       0 "victory"
//   level up                        0 "victory"
//   coin                            4 "miss"
//   a pipe passed                   5 "hit"
//
//   the level goes up one clock after the score pulse , so all the pulses are delayed by one clock here :
//   then all the events of one pipe pass arrive in the same clock , and the priority chooses one song

module	flappy_sound_control	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	scorePulse,          // from pipes_controller
	input	logic	hitPulse,            // from flappy_collision_detector
	input	logic	coinPulse,
	input	logic	shieldPulse,
	input	logic	shatterPulse,
	input	logic	hourglassPulse,
	input	logic	confusePulse,
	input	logic	[2:0] level,         // from flappy_game_controller

	output	logic	[3:0] melodySelect,  // to AUDIO keyPad ( held until the next event )
	output	logic	startMelody          // to AUDIO keypadValid
);

localparam logic [3:0] SONG_VICTORY   = 4'd0 ;
localparam logic [3:0] SONG_FAILURE   = 4'd2 ;
localparam logic [3:0] SONG_EXPLOSION = 4'd3 ;
localparam logic [3:0] SONG_MISS      = 4'd4 ;
localparam logic [3:0] SONG_HIT       = 4'd5 ;
localparam logic [4:0] START_CLOCKS   = 5'd16 ;   // the length of the start pulse

//////////--------------------------------------------------------------------------------------------------------------=
// the pulses delayed by one clock , and "the level went up"
logic [2:0] level_d ;
logic scorePulse_d , hitPulse_d , coinPulse_d , shieldPulse_d , shatterPulse_d , hourglassPulse_d , confusePulse_d ;
logic levelUp ;

assign levelUp = (level > level_d) ;   // a new game sets the level back to 0 - that is not a level up

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		level_d          <= 3'd0 ;
		scorePulse_d     <= 1'b0 ;
		hitPulse_d       <= 1'b0 ;
		coinPulse_d      <= 1'b0 ;
		shieldPulse_d    <= 1'b0 ;
		shatterPulse_d   <= 1'b0 ;
		hourglassPulse_d <= 1'b0 ;
		confusePulse_d   <= 1'b0 ;
	end
	else begin
		level_d          <= level ;
		scorePulse_d     <= scorePulse ;
		hitPulse_d       <= hitPulse ;
		coinPulse_d      <= coinPulse ;
		shieldPulse_d    <= shieldPulse ;
		shatterPulse_d   <= shatterPulse ;
		hourglassPulse_d <= hourglassPulse ;
		confusePulse_d   <= confusePulse ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// which song now ? ( a priority list - the first true event wins )
logic       playNow ;
logic [3:0] song ;

always_comb
begin
	playNow = 1'b1 ;
	song    = SONG_HIT ;
	if (hitPulse_d)                            song = SONG_EXPLOSION ;
	else if (shatterPulse_d)                   song = SONG_EXPLOSION ;
	else if (confusePulse_d)                   song = SONG_FAILURE ;
	else if (shieldPulse_d || hourglassPulse_d) song = SONG_VICTORY ;
	else if (levelUp)                          song = SONG_VICTORY ;
	else if (coinPulse_d)                      song = SONG_MISS ;
	else if (scorePulse_d)                     song = SONG_HIT ;
	else                                       playNow = 1'b0 ;    // no event
end

// remember the song and give a start pulse of 16 clocks ( long enough for the AUDIO block to see it )
logic [4:0] startCounter ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		melodySelect <= SONG_HIT ;
		startCounter <= 5'd0 ;
	end
	else if (playNow) begin
		melodySelect <= song ;
		startCounter <= START_CLOCKS ;
	end
	else if (startCounter != 5'd0)
		startCounter <= startCounter - 5'd1 ;
end

assign startMelody = (startCounter != 5'd0) ;

endmodule
