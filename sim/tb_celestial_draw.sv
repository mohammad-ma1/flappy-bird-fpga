// self checking testbench for celestial_draw ( the sun and the moon of the day / night cycle )
// streams full frames and checks every pixel 2 clocks later against a reference model , at several moments of the cycle
`timescale 1ns/1ps

module tb_celestial_draw;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY;
logic [8:0]  dayStep;
logic [2:0]  level;
logic drawingRequest;
logic [7:0] RGBout;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

celestial_draw dut (.*);

// reference : the position on the arc and the shapes
int bx, by, moon;
task automatic set_cycle(input int cyc, input int lv);
	int t, dx;
	dayStep = 9'(cyc >> 3); level = 3'(lv);   // dayStep = dayCycle / 8
	moon = (lv >= 2);
	t  = cyc & 4095;
	bx = 64 + t / 8;
	dx = bx - 320;
	by = 40 + (dx * dx) / 512 + ((lv == 1) ? 70 : 0);   // the sunset sun is lower
endtask

function automatic logic [7:0] model(input int x, y);
	int dx, dy, r2, s2;
	dx = x - bx; dy = y - by; r2 = dx*dx + dy*dy;
	s2 = (dx - 7) * (dx - 7) + (dy + 4) * (dy + 4);
	if (moon) begin
		if (r2 < 14*14 && !(s2 < 14*14)) return 8'hFE;     // the white crescent
		return 8'hFF;
	end
	if (r2 < 14*14) return 8'hFC;                         // yellow sun
	if (r2 < 18*18) return 8'hF4;                         // orange rim
	return 8'hFF;
endfunction

logic [7:0] exp_q[$];
int pixels, minX, maxX, minY, maxY;

task automatic compare(input string name, input int px, input int py);
	logic [7:0] e;
	e = exp_q.pop_front();
	checks++;
	if (RGBout !== e || drawingRequest !== (e != 8'hFF)) begin
		errors++;
		if (errors < 10) $display("FAIL %s : %h expected %h", name, RGBout, e);
	end
	if (drawingRequest) begin
		pixels++;
		if (px < minX) minX = px; if (px > maxX) maxX = px;
		if (py < minY) minY = py; if (py > maxY) maxY = py;
	end
endtask

int qx[$], qy[$];
task automatic scan_frame(input string name);
	pixels = 0; minX = 9999; maxX = -1; minY = 9999; maxY = -1;
	for (int y = 0; y < 480; y++)
		for (int x = 0; x < 640; x++) begin
			@(negedge clk);
			if (exp_q.size() == 2) begin compare(name, qx.pop_front(), qy.pop_front()); end
			pixelX = 11'(x); pixelY = 11'(y);
			exp_q.push_back(model(x, y)); qx.push_back(x); qy.push_back(y);
		end
	repeat (2) begin @(negedge clk); compare(name, qx.pop_front(), qy.pop_front()); end
	$display("%s : %0d pixels , X %0d..%0d , Y %0d..%0d ( center %0d , %0d )", name, pixels, minX, maxX, minY, maxY, bx, by);
endtask

task automatic check(input logic ok, input string what);
	checks++;
	if (!ok) begin errors++; $display("FAIL %s", what); end
endtask

int sunY0, sunYmid;

initial begin
	pixelX = 0; pixelY = 0;
	set_cycle(0, 0);
	resetN = 1'b0;
	#22 resetN = 1'b1;

	scan_frame("sunrise ( cycle 0 )");
	check(pixels > 900 && pixels < 1100 && bx == 64, "the sun : a full circle of radius 18 at the left");
	sunY0 = by;
	set_cycle(2048, 0);
	scan_frame("noon ( cycle 2048 , level 0 )");
	check(bx == 320 && by == 40 && minY == 23, "noon : the sun is high in the middle");
	sunYmid = by;
	check(sunY0 > sunYmid + 100, "the sun moves on an arc : low at the side , high in the middle");
	set_cycle(4095, 0);
	scan_frame("sunset ( cycle 4095 )");
	check(bx == 575 && pixels > 900, "sunset : the sun at the right");
	set_cycle(2048, 1);
	scan_frame("sunset scene ( level 1 )");
	check(by == 110 && pixels > 900, "level 1 ( sunset ) : the sun is 70 pixels lower");
	set_cycle(4096 + 2048, 2);
	scan_frame("night scene ( level 2 )");
	check(pixels > 150 && pixels < 500 && bx == 320, "the moon : a white crescent ( smaller than the full circle )");
	set_cycle(1000, 5);
	scan_frame("night scene ( level 5 )");
	check(pixels > 150, "the moon moves too");

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
