// integration testbench for flappy_game_core ( all the game modules together ) - run with sim\run_core.ps1 ( Verilator )
//  - the testbench is the VGA scan : full frames ( 640x480 ) for screenshots , fast frames ( only the columns
//    around the bird , enough for collisions ) for long games
//  - a bot player reads the bird and the active gap and presses up / down
//  - screenshots are written to sim/out/*.ppm ( 640x480 , colors expanded like VGA_Controller )
`timescale 1ns/1ps

module tb_flappy_game_core;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY;
logic startOfFrame, startKey, keyUp, keyDown, cheatNoDeath, turbo;
logic [7:0]  RGBOut;
logic [1:0]  gameState;
logic [15:0] scoreBCD, highScoreBCD;
logic [2:0]  level;
logic shieldActive, slowMoActive, invertControls;
logic [3:0]  melodySelect;
logic startMelody;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_game_core dut (.*);

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s (state=%0d score=%h best=%h level=%0d)", what, gameState, scoreBCD, highScoreBCD, level); end
	else $display("ok   %s", what);
endtask

// ---------------- event counters
int hits, scores, coins, sCoins, spotFrames, songStarts [0:15];
int newShields, newPipes, oldItems, hiddenFrames, hiddenEarly, hitsWhileHidden;
int glasses, purples, slowFrames, slowTicks, confusedFrames;
int pipeX_d [0:5] = '{0, 0, 0, 0, 0, 0};   // the pipe X of the clock before
int shields, shatters, shieldFrames;
logic startMelody_d = 1'b0;
always @(posedge clk) begin
	if (dut.hitPulse) hits++;
	if (dut.scorePulse) scores++;
	if (dut.coinPulse) coins++;
	if (dut.coinPulse && dut.pipes_controller_inst.itemAtBird) sCoins++;
	if (startOfFrame && dut.nightMode && gameState == 2'd1) spotFrames++;
	if (startOfFrame && gameState == 2'd1 && !dut.pipesVisible) begin hiddenFrames++; if (level < 3) hiddenEarly++; end
	if (dut.collision && !dut.pipesVisible && gameState == 2'd1) hitsWhileHidden++;   // invisible pipes still collide
	if (dut.hourglassPulse) glasses++;
	if (dut.confusePulse) purples++;
	if (startOfFrame && gameState == 2'd1 && slowMoActive) begin slowFrames++; if (dut.gameTick) slowTicks++; end   // half speed
	if (startOfFrame && invertControls) confusedFrames++;

	if (startMelody && !startMelody_d) songStarts[melodySelect]++;
	for (int k = 0; k < 6; k++) if (dut.pipeX[k] > pipeX_d[k] + 100) begin   // pipe k recycled
		newPipes++;
		if (dut.itemOn[k] && dut.itemKind[k] == 2'd1) newShields++;
		if (dut.edgeCoin[k] == 2'd3) oldItems++;           // item code 3 ( the old poison ) must never appear
	end
	for (int k = 0; k < 6; k++) pipeX_d[k] <= dut.pipeX[k];
	if (dut.shieldPulse) shields++;
	if (dut.shatterPulse) shatters++;
	if (startOfFrame && shieldActive) shieldFrames++;
	startMelody_d <= startMelody;
end

task automatic clear_counters();
	hits = 0; scores = 0; coins = 0; sCoins = 0; spotFrames = 0;
	newShields = 0; newPipes = 0; oldItems = 0; hiddenFrames = 0; hiddenEarly = 0; hitsWhileHidden = 0;
	glasses = 0; purples = 0; slowFrames = 0; slowTicks = 0; confusedFrames = 0;
	shields = 0; shatters = 0; shieldFrames = 0;
	for (int i = 0; i < 16; i++) songStarts[i] = 0;
endtask

// ---------------- the VGA scan
localparam int LATENCY = 3;     // draw modules 2 clocks + objects_mux 1 clock
logic [7:0] image [0:479][0:639];

task automatic start_of_frame();
	@(negedge clk) begin pixelX = 0; pixelY = 0; startOfFrame = 1'b1; end
	@(negedge clk) startOfFrame = 1'b0;
	repeat (8) @(negedge clk);
endtask

// full frame : every pixel , 16 blanking clocks per row ( pixelX = 0 like VGA_Controller ) , RGB captured
task automatic full_frame();
	start_of_frame();
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 640 + 16; x++) begin
			@(negedge clk);
			if (x >= LATENCY && x < 640 + LATENCY) image[y][x - LATENCY] = RGBOut;
			pixelX = 11'(x < 640 ? x : 0); pixelY = 11'(y);
		end
endtask

// fast frame : only X 140..215 ( the bird is at X 160..191 ) - collisions and game logic are exact
task automatic fast_frame();
	start_of_frame();
	for (int y = 0; y < 480; y++)
		for (int x = 140; x < 216; x++) begin
			@(negedge clk);
			pixelX = 11'(x); pixelY = 11'(y);
		end
endtask

// ---------------- screenshot : P3 ppm , 3-3-2 expanded like VGA_Controller
task automatic save_image(input string name);
	int fd, r, g, b;
	fd = $fopen(name, "w");
	$fwrite(fd, "P3\n640 480\n255\n");
	for (int y = 0; y < 480; y++) begin
		for (int x = 0; x < 640; x++) begin
			r = {image[y][x][7:5], image[y][x][7:5], image[y][x][7:6]};
			g = {image[y][x][4:2], image[y][x][4:2], image[y][x][4:3]};
			b = {image[y][x][1:0], image[y][x][1:0], image[y][x][1:0], image[y][x][1:0]};
			$fwrite(fd, "%0d %0d %0d ", r, g, b);
		end
		$fwrite(fd, "\n");
	end
	$fclose(fd);
	$display("     screenshot %s", name);
endtask

// ---------------- the bot : move the active gap toward the bird
logic bot = 1'b0;
int birdCenter, gapCenter, halfGap;
logic wantUp, wantDown;
always @(posedge startOfFrame) begin
	if (bot) begin
		// the gap center goes to the bird center ( 240 ) - or , to collect a coin , near the coin edge :
		// top coin : gap top 222 ( the tube ends at 221 , the bird pixels start at 232 ) -> center 286
		// bottom coin : gap bottom 255 ( the bird pixels end at 246 ) -> center 191
		// a scattered coin ahead of the bird : put the coin center on the bird center ( coin Y = pipeY + dy )
		// the gaps have random heights ( gapH ) : the targets use the half gap of the active pipe
		halfGap = dut.pipes_controller_inst.gapH[dut.activeIndex] / 2;
		if (dut.itemOn[dut.activeIndex] && (dut.itemX[dut.activeIndex] + 16 > dut.birdTopLeftX))
			birdCenter = 240 + halfGap - 8 - int'(dut.pipes_controller_inst.itemDY[dut.activeIndex]);
		else case (dut.edgeCoin[dut.activeIndex])
			2'd1:    birdCenter = 222 + halfGap;
			2'd2:    birdCenter = 255 - halfGap;
			default: birdCenter = dut.birdTopLeftY + 16;
		endcase
		gapCenter  = dut.pipes_controller_inst.pipeY[dut.activeIndex] + halfGap;
		wantUp   = (gapCenter > birdCenter + 2);                     // the gap is below the bird -> move it up
		wantDown = (gapCenter < birdCenter - 2);
		keyUp    = invertControls ? wantDown : wantUp;     // the purple trap swaps the keys : the bot swaps them back
		keyDown  = invertControls ? wantUp : wantDown;
	end
end

task automatic press_start();
	startKey = 1'b1; repeat (2) fast_frame(); startKey = 1'b0; fast_frame();
endtask

function automatic int bcd(input logic [15:0] v);
	return v[15:12]*1000 + v[11:8]*100 + v[7:4]*10 + v[3:0];
endfunction

int f, colors, framesToCrash, yMoves, nightScores, x0 [0:5], y0 [0:5];
logic [7:0] seen [0:255];

initial begin
	{startOfFrame, startKey, keyUp, keyDown, cheatNoDeath, turbo} = '0;
	pixelX = 0; pixelY = 0;
	clear_counters();
	resetN = 1'b0;
	#22 resetN = 1'b1;

	// ---- START screen
	full_frame(); full_frame();
	save_image("screen_start.ppm");
	check(gameState == 2'd0, "after reset : START");
	colors = 0;
	for (int i = 0; i < 256; i++) seen[i] = 0;
	for (int y = 0; y < 480; y++) for (int x = 0; x < 640; x++) seen[image[y][x]] = 1;
	for (int i = 0; i < 256; i++) colors += seen[i];
	check(colors > 10, $sformatf("START screen has %0d colors", colors));

	// ---- NORMAL game , no cheat : the bot plays to score 9
	press_start();
	check(gameState == 2'd1 && scoreBCD == 0, "ENTER : PLAY , score 0");
	bot = 1'b1;
	for (f = 0; f < 6000 && gameState == 2'd1 && bcd(scoreBCD) < 9; f++) fast_frame();
	$display("     no-cheat game : score %0d , level %0d after %0d frames , %0d coins ( %0d scattered )",
	         bcd(scoreBCD), level, f, coins, sCoins);
	check(gameState == 2'd1 && bcd(scoreBCD) >= 9, "the bot reaches score 9 without dying");
	check(sCoins > 0, "scattered coins collected without dying ( reachable with the fixed bird )");

	// ---- the same game with no-death : coins , shield items , night mode
	cheatNoDeath = 1'b1;
	repeat (100) fast_frame();
	full_frame(); full_frame();
	save_image("screen_play.ppm");
	for (f = 0; f < 8000 && !dut.nightMode; f++) fast_frame();         // temporary night mode at score 15
	check(dut.nightMode && (bcd(scoreBCD) % 15) <= 1, "night mode starts at a multiple of 15 ( 15 , 30 , 45 ... )");
	nightScores = scores;
	repeat (5) fast_frame();
	full_frame();
	save_image("screen_play_spotlight.ppm");
	for (f = 0; f < 3000 && dut.nightMode; f++) fast_frame();                // 6 frames were already played in the dark
	$display("     night mode lasted %0d frames ( %0d pipes passed in the dark )", f + 6, scores - nightScores);
	check(!dut.nightMode && f + 6 >= 364 && f + 6 <= 366, "night mode lasts exactly 5 seconds ( 365 frames ) , passing pipes does not end it");
	for (f = 0; f < 8000 && bcd(scoreBCD) < 24; f++) fast_frame();
	// the rare items ( 1 of 16 new pipes each ) : play on until a shield , an hourglass and a purple trap were collected
	for (f = 0; f < 20000 && (shields == 0 || glasses == 0 || purples == 0) && bcd(scoreBCD) < 400; f++) fast_frame();
	repeat (60) fast_frame();                         // let the last collected item act for a moment ( e.g. slow motion )
	$display("     cheat game : score %0d , level %0d , %0d coins , %0d spotlight frames , %0d hits ignored",
	         bcd(scoreBCD), level, coins, spotFrames, hits);
	check(coins > 0 && oldItems == 0, "coins collected , no poison item ever appears");
	check(spotFrames > 0, "night mode happened");
	check(bcd(scoreBCD) == scores + 2 * coins, "score = pipes + 2 x coins");
	check(songStarts[5] > 0 && songStarts[0] > 0 && songStarts[4] > 0, "songs : score , level up , coin");
	$display("     new pipes : %0d , %0d with a shield", newPipes, newShields);
	$display("     shield : %0d collected ( %0d shielded frames , %0d pipes shattered )",
	         shields, shieldFrames, shatters);

	$display("     rare items : %0d hourglasses ( %0d slow frames , %0d game ticks in them ) , %0d purple traps ( %0d confused frames )",
	         glasses, slowFrames, slowTicks, purples, confusedFrames);
	check(glasses == 0 || (slowFrames > 0 && slowTicks * 2 >= slowFrames - 1 && slowTicks * 2 <= slowFrames + 1), "slow motion : the game updates every 2nd frame ( half speed )");
	check(glasses > 0 && purples > 0, "hourglasses and purple traps appeared and were collected");
	check(slowFrames <= glasses * 730 && confusedFrames <= purples * 511, "slow motion <= 10 s , swapped keys <= 7 s per item");
	$display("     invisible maze : %0d invisible frames ( %0d below score 30 ) , %0d colliding pixels while invisible", hiddenFrames, hiddenEarly, hitsWhileHidden);
	check(hiddenFrames > 0 && hiddenEarly == 0, "the pipes blink invisible , only from score 30");
	check(shields > 0, "ghost shield items appeared and were collected");
	check(shieldFrames <= shields * 730, "the shield lasts at most 10 seconds");
	cheatNoDeath = 1'b0;

	// ---- no player : crash -> GAME_OVER
	bot = 1'b0; keyUp = 1'b0; keyDown = 1'b0;
	framesToCrash = 0;
	while (gameState == 2'd1 && framesToCrash < 4000) begin fast_frame(); framesToCrash++; end
	$display("     crash after %0d frames without the player", framesToCrash);
	check(gameState == 2'd2, "no player -> crash -> GAME_OVER");
	check(highScoreBCD == scoreBCD && scoreBCD != 0, "high score = final score");
	full_frame(); full_frame();
	save_image("screen_game_over.ppm");
	// GAME OVER : everything is frozen ( pipes , sun / moon , background layers ) and the final score stays
	begin
		int px0; logic [8:0] dc0; logic [7:0] near0; logic [15:0] sc0;
		px0 = dut.pipeX[0] + dut.pipeX[3]; dc0 = dut.dayStep; near0 = dut.nearOffset; sc0 = scoreBCD;
		repeat (60) fast_frame();
		check(dut.pipeX[0] + dut.pipeX[3] == px0 && dut.dayStep == dc0 && dut.nearOffset == near0 && scoreBCD == sc0 && gameState == 2'd2,
		      "GAME OVER : all movement frozen , the final score stays");
	end

	// ---- ENTER restarts : a new game from score 0 . STATIC PIPES ( user decision ) : no keys ( cheat on , so the game
	//      goes on ) up to the advanced levels - no pipe may ever move up or down by itself while it scrolls
	bot = 1'b0; keyUp = 1'b0; keyDown = 1'b0; cheatNoDeath = 1'b1;
	press_start();
	// press_start runs 2 more frames in PLAY , so the first pipe already scrolled up to 3 pixels from X 512
	check(gameState == 2'd1 && level == 0 && scoreBCD == 0 && dut.pipeX[0] >= 12'sd509 && dut.pipeX[0] <= 12'sd512,
	      $sformatf("ENTER after GAME OVER : PLAY again , score 0 , level 0 , the pipes placed again ( first pipe X %0d )", int'(dut.pipeX[0])));
	yMoves = 0;
	for (int fr = 0; fr < 9000 && level < 5; fr++) begin
		for (int k = 0; k < 6; k++) begin x0[k] = dut.pipeX[k]; y0[k] = dut.pipes_controller_inst.pipeY[k]; end
		fast_frame();
		for (int k = 0; k < 6; k++)
			if (dut.pipeX[k] <= x0[k] && dut.pipes_controller_inst.pipeY[k] != y0[k]) yMoves++;   // scrolled , not placed again
	end
	$display("     no keys up to level %0d ( score %0d ) : %0d pipe Y moves", level, bcd(scoreBCD), yMoves);
	check(level >= 5 && yMoves == 0, "static pipes : without keys no pipe ever moves up or down , also in the advanced levels");
	full_frame(); full_frame();
	save_image("screen_static.ppm");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
