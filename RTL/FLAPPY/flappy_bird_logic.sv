// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// flappy_bird_logic : the bird of the controlled maze
//   the bird is FIXED in its place ( X and Y never change ) - the screen scrolls and the player moves the
//   pipes up / down to bring the gap to the bird . only the wings move ( animation frame for flappy_bird_draw )

module	flappy_bird_logic	(
					input	logic	clk,
					input	logic	resetN,
					input	logic	startOfFrame,   // short pulse every start of frame
					input	logic	playEnable,     // the wings move only while playing (from game_controller)
					input	logic	newGamePulse,   // a new game starts with the wings up (from game_controller)

					output	logic signed	[10:0] topLeftX, // output the top left corner ( fixed )
					output	logic signed	[10:0] topLeftY,
					output	logic	flapFrame                   // wing animation frame for flappy_bird_draw
);

parameter int BIRD_X = 160;   // fixed X of the bird ( pipes_controller gets it as birdX )
parameter int BIRD_Y = 224;   // fixed Y of the bird : the middle of the screen ( 240 - 32/2 )

logic [3:0] flapCounter ;      // counts the frames 0..15 , then 0 again

//////////--------------------------------------------------------------------------------------------------------------=
// wing animation : counts frames while playing
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN)
		flapCounter <= 4'd0 ;
	else begin
		if (newGamePulse)
			flapCounter <= 4'd0 ;                  // a new game starts with the wings up
		else if (startOfFrame && playEnable)
			flapCounter <= flapCounter + 4'd1 ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// outputs
assign topLeftX  = 11'(BIRD_X) ;
assign topLeftY  = 11'(BIRD_Y) ;
assign flapFrame = flapCounter[3] ;     // the top bit : 0 for 8 frames , 1 for 8 frames - the wings change every 8 frames

endmodule
