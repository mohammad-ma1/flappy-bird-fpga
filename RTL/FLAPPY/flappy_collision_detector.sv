// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
//
// flappy_collision_detector : what did the bird touch ?  ( based on the course game_controller )
//
//   no geometry is needed : if in the same pixel the bird wants to draw AND another object wants to draw ,
//   they overlap on the screen = a collision . one AND gate for every kind :
//     bird AND ( pipe OR border )  -> hitPulse       ( game over )
//     bird AND pipe , with shield  -> shatterPulse   ( the pipe breaks , the shield is used )
//     bird AND shield item         -> shieldPulse
//     bird AND hourglass           -> hourglassPulse
//     bird AND purple trap         -> confusePulse
//     bird AND coin                -> coinPulse
//   the bird touches many pixels of an object , but every kind gives only ONE pulse per frame :
//   a flag for every kind is cleared at the start of the frame and set by the first touch
//   the drawing requests come 2 clocks after their pixel , so pixelY is delayed by 2 clocks here ( for the border )

module	flappy_collision_detector	(
	input	logic	clk,
	input	logic	resetN,
	input	logic	startOfFrame,              // a pulse at the start of every frame
	input	logic	playEnable,                // detect only while playing
	input	logic	signed [10:0] pixelY,      // the current VGA pixel row
	input	logic	birdDrawingRequest,        // from flappy_bird_draw
	input	logic	pipesDrawingRequest,       // from pipes_draw
	input	logic	coinDrawingRequest,        // from items_draw
	input	logic	shieldItemDrawingRequest,
	input	logic	hourglassDrawingRequest,
	input	logic	confuseDrawingRequest,
	input	logic	shieldActive,              // from flappy_game_controller

	output	logic	collision,                 // 1 in every lethal pixel ( for the testbench )
	output	logic	hitPulse,                  // one pulse per frame at most , for every kind
	output	logic	coinPulse,
	output	logic	shieldPulse,
	output	logic	shatterPulse,
	output	logic	hourglassPulse,
	output	logic	confusePulse
);

parameter int BORDER_WIDTH  = 2;     // the top 2 rows and the bottom 2 rows kill the bird
parameter int SCREEN_HEIGHT = 480;

//////////--------------------------------------------------------------------------------------------------------------=
// pixelY of 2 clocks ago : the row of the pixel whose drawing requests arrive now
logic signed [10:0] pixelY_d1 , pixelY_d2 ;

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		pixelY_d1 <= 11'sd240 ;   // the middle of the screen - not a border
		pixelY_d2 <= 11'sd240 ;
	end
	else begin
		pixelY_d1 <= pixelY ;
		pixelY_d2 <= pixelY_d1 ;
	end
end

//////////--------------------------------------------------------------------------------------------------------------=
// the touches ( combinational : an AND of two drawing requests )
logic border ;
logic pipeTouch , coinTouch , shieldTouch , hourglassTouch , confuseTouch ;
logic hitFlag , coinFlag , shieldFlag , shatterFlag , hourglassFlag , confuseFlag ;   // "already happened in this frame"

assign border         = (int'(pixelY_d2) < BORDER_WIDTH) || (int'(pixelY_d2) >= SCREEN_HEIGHT - BORDER_WIDTH) ;
assign pipeTouch      = birdDrawingRequest && pipesDrawingRequest ;
assign coinTouch      = birdDrawingRequest && coinDrawingRequest ;
assign shieldTouch    = birdDrawingRequest && shieldItemDrawingRequest ;
assign hourglassTouch = birdDrawingRequest && hourglassDrawingRequest ;
assign confuseTouch   = birdDrawingRequest && confuseDrawingRequest ;

// lethal : a pipe without the shield ( and not the pipe that the shield just broke ) , or the border ( always )
assign collision = (pipeTouch && !shieldActive && !shatterFlag) || (birdDrawingRequest && border) ;

//////////--------------------------------------------------------------------------------------------------------------=
// one pulse of every kind per frame
always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		hitFlag       <= 1'b0 ;  hitPulse       <= 1'b0 ;
		coinFlag      <= 1'b0 ;  coinPulse      <= 1'b0 ;
		shieldFlag    <= 1'b0 ;  shieldPulse    <= 1'b0 ;
		shatterFlag   <= 1'b0 ;  shatterPulse   <= 1'b0 ;
		hourglassFlag <= 1'b0 ;  hourglassPulse <= 1'b0 ;
		confuseFlag   <= 1'b0 ;  confusePulse   <= 1'b0 ;
	end
	else begin
		// defaults : a pulse lasts one clock
		hitPulse       <= 1'b0 ;
		coinPulse      <= 1'b0 ;
		shieldPulse    <= 1'b0 ;
		shatterPulse   <= 1'b0 ;
		hourglassPulse <= 1'b0 ;
		confusePulse   <= 1'b0 ;

		// a new frame : clear all the flags
		if (startOfFrame) begin
			hitFlag       <= 1'b0 ;
			coinFlag      <= 1'b0 ;
			shieldFlag    <= 1'b0 ;
			shatterFlag   <= 1'b0 ;
			hourglassFlag <= 1'b0 ;
			confuseFlag   <= 1'b0 ;
		end

		// the first touch of a kind in this frame : set its flag and give its pulse
		if (playEnable) begin
			if (collision && !hitFlag) begin
				hitFlag  <= 1'b1 ;
				hitPulse <= 1'b1 ;
			end
			if (pipeTouch && shieldActive && !shatterFlag) begin     // the shield breaks the pipe
				shatterFlag  <= 1'b1 ;
				shatterPulse <= 1'b1 ;
			end
			if (coinTouch && !coinFlag) begin
				coinFlag  <= 1'b1 ;
				coinPulse <= 1'b1 ;
			end
			if (shieldTouch && !shieldFlag) begin
				shieldFlag  <= 1'b1 ;
				shieldPulse <= 1'b1 ;
			end
			if (hourglassTouch && !hourglassFlag) begin
				hourglassFlag  <= 1'b1 ;
				hourglassPulse <= 1'b1 ;
			end
			if (confuseTouch && !confuseFlag) begin
				confuseFlag  <= 1'b1 ;
				confusePulse <= 1'b1 ;
			end
		end
	end
end

endmodule
