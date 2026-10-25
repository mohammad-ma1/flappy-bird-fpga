// self checking testbench for flappy_collision_detector
// frames of 480 rows x 16 pixels , the drawing requests are generated from rectangles and delayed by
// 2 clocks exactly like flappy_bird_draw / flappy_pipes_draw , so the border alignment is tested too
`timescale 1ns/1ps

module tb_flappy_collision_detector;

logic clk = 1'b0;
logic resetN, startOfFrame, playEnable;
logic signed [10:0] pixelY;
logic birdDrawingRequest, pipesDrawingRequest, coinDrawingRequest;
logic shieldItemDrawingRequest, shieldActive, hourglassDrawingRequest, confuseDrawingRequest;
logic collision, hitPulse, coinPulse, shieldPulse, shatterPulse, hourglassPulse, confusePulse;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_collision_detector dut (.*);

// the objects : rectangles of rows / columns
int birdY0, birdY1, birdX0, birdX1;
int pipeY0, pipeY1, pipeX0, pipeX1;
int itemY0, itemY1, itemX0, itemX1, itemKind;   // a second object : 2 coin , 4 shield item , 7 hourglass , 8 purple trap
logic signed [10:0] pixelX;
logic inFrame;
logic birdRaw, pipeRaw, birdRaw_d, pipeRaw_d, itemRaw, itemRaw_d, itemRaw_d2;

assign birdRaw = inFrame && pixelY >= birdY0 && pixelY <= birdY1 && pixelX >= birdX0 && pixelX <= birdX1;
assign pipeRaw = inFrame && pixelY >= pipeY0 && pipeY1 >= pixelY && pixelX >= pipeX0 && pixelX <= pipeX1;
assign itemRaw = inFrame && pixelY >= itemY0 && itemY1 >= pixelY && pixelX >= itemX0 && pixelX <= itemX1;
assign coinDrawingRequest   = itemRaw_d2 && (itemKind == 2);
assign shieldItemDrawingRequest = itemRaw_d2 && (itemKind == 4);
assign hourglassDrawingRequest  = itemRaw_d2 && (itemKind == 7);
assign confuseDrawingRequest    = itemRaw_d2 && (itemKind == 8);

// 2 clocks latency like the draw modules
always_ff @(posedge clk) begin
	birdRaw_d <= birdRaw;            birdDrawingRequest  <= birdRaw_d;
	pipeRaw_d <= pipeRaw;            pipesDrawingRequest <= pipeRaw_d;
	itemRaw_d <= itemRaw;            itemRaw_d2 <= itemRaw_d;
end

int pulses, collisions, firstCollision, firstPulse, clockCount, coins, shields, shatters, hourglasses, confusions;
always @(posedge clk) begin
	clockCount++;
	if (coinPulse) coins++;
	if (shieldPulse) shields++;
	if (hourglassPulse) hourglasses++;
	if (confusePulse) confusions++;
	if (shatterPulse) shatters++;
	if (hitPulse) begin
		pulses++;
		if (firstPulse < 0) firstPulse = clockCount;
	end
	if (collision) begin
		collisions++;
		if (firstCollision < 0) firstCollision = clockCount;
	end
end

// one frame : start of frame pulse in the blanking , 480 rows of 16 pixels , blanking ( pixelY = 0 like VGA_Controller )
task automatic frame();
	@(negedge clk) begin inFrame = 1'b0; pixelX = 0; pixelY = 0; startOfFrame = 1'b1; end
	@(negedge clk) startOfFrame = 1'b0;
	repeat (5) @(negedge clk);
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 16; x++) begin
			@(negedge clk);
			inFrame = 1'b1; pixelX = 11'(x); pixelY = 11'(y);
		end
	@(negedge clk) begin inFrame = 1'b0; pixelX = 0; pixelY = 0; end
	repeat (5) @(negedge clk);
endtask

task automatic run(input int frames, input int expPulses, input string name);
	pulses = 0; collisions = 0; firstCollision = -1; firstPulse = -1; coins = 0; shields = 0; shatters = 0; hourglasses = 0; confusions = 0;
	repeat (frames) frame();
	checks++;
	if (pulses != expPulses) begin
		errors++; $display("FAIL %s : %0d pulses , expected %0d", name, pulses, expPulses);
	end
	else $display("%s : %0d pulses in %0d frames , %0d colliding pixels", name, pulses, frames, collisions);
endtask

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

task automatic set_bird(input int y0, y1, x0, x1); birdY0 = y0; birdY1 = y1; birdX0 = x0; birdX1 = x1; endtask
task automatic set_pipe(input int y0, y1, x0, x1); pipeY0 = y0; pipeY1 = y1; pipeX0 = x0; pipeX1 = x1; endtask
task automatic set_item(input int kind, y0, y1, x0, x1); itemKind = kind; itemY0 = y0; itemY1 = y1; itemX0 = x0; itemX1 = x1; endtask

initial begin
	{startOfFrame, playEnable, inFrame, shieldActive} = '0;
	pixelX = 0; pixelY = 0; clockCount = 0;
	set_bird(200, 231, 4, 7);
	set_pipe(-1, -1, 0, 0);       // no pipe
	set_item(0, -1, -1, 0, 0);    // no item
	resetN = 1'b0;
	#22 resetN = 1'b1;
	playEnable = 1'b1;

	// no overlap
	set_pipe(0, 150, 0, 15);
	run(3, 0, "bird below the pipe");
	check(collisions == 0, "no colliding pixels");

	// overlap of 11 rows x 4 columns : exactly one pulse per frame
	set_pipe(0, 210, 0, 15);
	run(5, 5, "bird inside the pipe");
	check(collisions == 5 * 11 * 4, "44 colliding pixels per frame");
	check(firstPulse == firstCollision + 1, "the pulse comes one clock after the first colliding pixel");

	// pipe alone ( bird elsewhere ) and bird alone
	set_bird(300, 331, 4, 7);
	run(2, 0, "pipe without the bird");

	// borders : rows 0..1 and 478..479
	set_pipe(-1, -1, 0, 0);
	set_bird(0, 31, 0, 15);
	run(3, 3, "bird touches the top edge");
	set_bird(2, 33, 0, 15);
	run(3, 0, "bird 2 rows below the top edge");
	set_bird(447, 478, 0, 15);
	run(3, 3, "bird touches the bottom edge");
	// the last bird pixel ( row 477 , X 15 ) reaches the detector when the screen is already at row 478 :
	// this passes only because pixelY is delayed by 2 clocks like the drawing requests
	set_bird(446, 477, 0, 15);
	run(3, 0, "bird 2 rows above the bottom edge (alignment)");

	// not playing : collision is seen but no pulse
	set_pipe(0, 479, 0, 15);
	set_bird(200, 231, 4, 7);
	playEnable = 1'b0;
	run(2, 0, "overlap while not playing");
	check(collisions == 2 * 32 * 4, "collision output still active while not playing");
	playEnable = 1'b1;
	run(2, 2, "overlap while playing again");

	set_pipe(-1, -1, 0, 0);
	set_bird(200, 231, 4, 7);

	// coin : +2 , one coinPulse per frame , not lethal
	set_item(2, 220, 236, 4, 10);
	run(3, 0, "bird touches a coin ( not lethal )");
	check(coins == 3 && shields == 0, "coin : exactly one coinPulse per frame");

	// a coin and a pipe in the same frame : both pulses ( separate flags )
	set_item(2, 200, 205, 4, 7);
	set_pipe(225, 260, 0, 15);
	run(2, 2, "coin and pipe in the same frame");
	check(coins == 2, "the coin pulse is not blocked by the lethal flag");

	// no pulses while not playing
	playEnable = 1'b0;
	run(2, 0, "not playing");
	check(coins == 0, "no coin pulse while not playing");
	playEnable = 1'b1;

	// hourglass : one hourglassPulse per frame , not lethal
	set_pipe(-1, -1, 0, 0);
	set_item(7, 220, 236, 4, 10);
	run(3, 0, "bird touches the hourglass ( not lethal )");
	check(hourglasses == 3 && coins == 0 && shields == 0 && confusions == 0, "hourglass : exactly one hourglassPulse per frame");

	// purple trap : one confusePulse per frame , not lethal
	set_item(8, 220, 236, 4, 10);
	run(3, 0, "bird touches the purple trap ( not lethal )");
	check(confusions == 3 && hourglasses == 0 && coins == 0, "purple trap : exactly one confusePulse per frame");
	set_item(0, -1, -1, 0, 0);

	// ghost shield item : one shieldPulse per frame , not lethal
	set_pipe(-1, -1, 0, 0);
	set_item(4, 220, 236, 4, 10);
	run(3, 0, "bird touches the shield item ( not lethal )");
	check(shields == 3 && coins == 0, "shield item : exactly one shieldPulse per frame");

	set_item(0, -1, -1, 0, 0);

	// shielded bird in a pipe : not lethal , one shatterPulse per frame , no colliding pixels
	shieldActive = 1'b1;
	set_pipe(0, 210, 0, 15);
	run(3, 0, "shielded bird inside the pipe");
	check(shatters == 3 && collisions == 0, "shield : one shatterPulse per frame , the pipe is not lethal");
	// the border stays lethal with the shield
	set_pipe(-1, -1, 0, 0);
	set_bird(0, 31, 0, 15);
	run(2, 2, "shielded bird touches the top edge ( still lethal )");
	shieldActive = 1'b0;
	set_bird(200, 231, 4, 7);

	#3 resetN = 1'b0; #1;
	check(hitPulse == 1'b0, "async reset");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
