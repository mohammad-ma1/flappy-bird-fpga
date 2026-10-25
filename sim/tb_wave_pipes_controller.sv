// a short game for the report waveform of pipes_controller ( not a self checking test )
// level 4 ( 2 pixels per frame , the gaps close in ) : UP for 20 frames , DOWN for 20 frames , then the bird passes pipe 0
// and pipe 0 leaves the screen and is placed again at the right . one row per frame in sim/out/wave_pipes_controller.csv
`timescale 1ns/1ps

module tb_wave_pipes_controller;

logic clk = 1'b0;
logic resetN, startOfFrame, playEnable, newGamePulse, turbo, keyUp, keyDown, invertControls;
logic coinPulse, shieldPulse, hourglassPulse, confusePulse, shatterPulse;
logic [2:0] level;
logic signed [10:0] birdX;
logic signed [11:0] pipeX     [0:5];
logic        [8:0]  gapTop    [0:5];
logic        [8:0]  gapBottom [0:5];
logic               broken    [0:5];
logic        [1:0]  edgeCoin  [0:5];
logic               itemOn    [0:5];
logic        [1:0]  itemKind  [0:5];
logic signed [11:0] itemX     [0:5];
logic        [8:0]  itemY     [0:5];
logic [2:0]  activeIndex;
logic        scorePulse;

always #5 clk = ~clk;

pipes_controller dut (.*);

int fd, fr, scored;
always @(posedge clk) if (scorePulse) scored = 1;

task automatic frame();
	@(negedge clk) startOfFrame = 1'b1;
	@(negedge clk) startOfFrame = 1'b0;
	repeat (2) @(negedge clk);
	$fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n", fr, keyUp, keyDown, activeIndex, scored,
	        pipeX[0], pipeX[1], gapTop[0], gapBottom[0]);
	scored = 0;
	fr++;
endtask

initial begin
	fd = $fopen("wave_pipes_controller.csv", "w");
	$fwrite(fd, "frame,keyUp,keyDown,activeIndex,scorePulse,pipeX0,pipeX1,gapTop0,gapBottom0\n");
	{startOfFrame, playEnable, newGamePulse, turbo, keyUp, keyDown, invertControls} = '0;
	{coinPulse, shieldPulse, hourglassPulse, confusePulse, shatterPulse} = '0;
	level = 3'd4; birdX = 11'sd160; fr = 0; scored = 0;
	resetN = 1'b0;
	#22 resetN = 1'b1;
	@(negedge clk) newGamePulse = 1'b1;
	@(negedge clk) newGamePulse = 1'b0;
	playEnable = 1'b1;
	repeat (20) frame();
	keyUp = 1'b1;   repeat (20) frame();  keyUp = 1'b0;     // the active pipe ( pipe 0 ) goes up
	repeat (15) frame();
	keyDown = 1'b1; repeat (20) frame();  keyDown = 1'b0;   // and down
	repeat (235) frame();                                   // the bird passes pipe 0 , pipe 0 leaves the screen
	$fclose(fd);
	$finish;
end

endmodule
