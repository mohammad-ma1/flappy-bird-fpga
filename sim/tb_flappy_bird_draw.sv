// self checking testbench for flappy_bird_draw
// the reference model is the original ASCII drawing of the bird ( independent of the hex tables in the RTL )
// pixels are streamed one per clock like the VGA controller , the output is checked 2 clocks later
`timescale 1ns/1ps

module tb_flappy_bird_draw;

logic clk = 1'b0;
logic resetN;
logic signed [10:0] pixelX, pixelY, topLeftX, topLeftY;
logic flapFrame;
logic drawingRequest;
logic [7:0] RGBout;

int errors = 0;
int checks = 0;

always #5 clk = ~clk;

flappy_bird_draw dut (.*);

// . transparent  K black  Y yellow  W white eye  O orange beak  R red mouth  L white wing  D dark yellow
logic [0:31][0:31][7:0] ART_WING_UP = {
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"...............KKKKKKKK.........",
	".............KKYYYYYKWWKK.......",
	"............KYYYYYYKWWWWWK......",
	"...........KYYYYYYKWWWWWWWK.....",
	"......KKKK.KYYYYYKWWWWWKWWK.....",
	".....KLLLLKKYYYYYKWWWWWKWWK.....",
	"....KLLLLLLKYYYYYKWWWWWKWWK.....",
	"....KLLLLLLLKYYYYYKWWWWWWWK.....",
	"....KYLLLLLKYYYYYYYKKKKKKKKK....",
	".....KYYYYKYYYYYYYKOOOOOOOOOK...",
	"......KKKKDDYYYYYKOKKKKKKKKK....",
	".......KDDDDDDDDKRRRRRRRRK......",
	".......KDDDDDDDDDKOOOOOOOOK.....",
	"........KKDDDDDDDDKKKKKKKK......",
	"..........KKKKKKKK..............",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................"
};
logic [0:31][0:31][7:0] ART_WING_DOWN = {
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"...............KKKKKKKK.........",
	".............KKYYYYYKWWKK.......",
	"............KYYYYYYKWWWWWK......",
	"...........KYYYYYYKWWWWWWWK.....",
	"...........KYYYYYKWWWWWKWWK.....",
	"..........KYYYYYYKWWWWWKWWK.....",
	".........KYYYYYYYKWWWWWKWWK.....",
	".....KKKKKYYYYYYYYKWWWWWWWK.....",
	"....KLLLLLKYYYYYYYYKKKKKKKKK....",
	"...KLLLLLLLKYYYYYYKOOOOOOOOOK...",
	"...KLLLLLLKDDYYYYKOKKKKKKKKK....",
	"....KKLLLKDDDDDDKRRRRRRRRK......",
	"......KKKDDDDDDDDKOOOOOOOOK.....",
	"........KKDDDDDDDDKKKKKKKK......",
	"..........KKKKKKKK..............",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................",
	"................................"
};

function automatic logic [7:0] char_color(input logic [7:0] c);
	case (c)
		"K": return 8'h00;
		"Y": return 8'hFC;
		"W": return 8'hFE;
		"O": return 8'hF0;
		"R": return 8'hE0;
		"L": return 8'hFE;
		"D": return 8'hD8;
		default: return 8'hFF;
	endcase
endfunction

function automatic logic [7:0] model(input int px, py, tlx, tly, input logic fr);
	int ox, oy;
	logic [0:31][7:0] row;
	ox = px - tlx; oy = py - tly;
	if (ox < 0 || ox > 31 || oy < 0 || oy > 31) return 8'hFF;
	row = fr ? ART_WING_DOWN[oy] : ART_WING_UP[oy];
	return char_color(row[ox]);
endfunction

int drawn;
logic [7:0] exp_q[$];

task automatic compare(input string name);
	logic [7:0] e;
	e = exp_q.pop_front();
	checks++;
	if (RGBout !== e || drawingRequest !== (e != 8'hFF)) begin
		errors++;
		if (errors < 10) $display("FAIL %s : RGB %h DR %b expected %h", name, RGBout, drawingRequest, e);
	end
	if (drawingRequest) drawn++;
endtask

// stream a window of pixels , one per clock
task automatic scan(input int tlx, tly, input logic fr, input int x0, x1, y0, y1, input string name);
	drawn = 0;
	@(negedge clk);
	topLeftX = 11'(tlx); topLeftY = 11'(tly); flapFrame = fr;
	for (int y = y0; y <= y1; y++)
		for (int x = x0; x <= x1; x++) begin
			@(negedge clk);
			if (exp_q.size() == 2) compare(name);
			pixelX = 11'(x); pixelY = 11'(y);
			exp_q.push_back(model(x, y, tlx, tly, fr));
		end
	repeat (2) begin @(negedge clk); compare(name); end
	$display("%s : %0d pixels drawn", name, drawn);
endtask

initial begin
	pixelX = 0; pixelY = 0; topLeftX = 11'sd100; topLeftY = 11'sd50; flapFrame = 1'b0;
	resetN = 1'b0;
	#22;
	checks++;
	if (drawingRequest !== 1'b0 || RGBout !== 8'hFF) begin errors++; $display("FAIL nothing drawn during reset"); end
	resetN = 1'b1;

	scan(100, 50, 1'b0,  90, 140,  40,  90, "wing up");
	if (drawn != 273) begin errors++; $display("FAIL wing up pixel count %0d != 273", drawn); end
	scan(100, 50, 1'b1,  90, 140,  40,  90, "wing down");
	if (drawn != 267) begin errors++; $display("FAIL wing down pixel count %0d != 267", drawn); end
	scan(-10, -12, 1'b0,  0,  30,   0,  30, "partly outside top-left (negative topLeft)");
	scan(620, 460, 1'b1, 600, 639, 440, 479, "partly outside bottom-right");
	scan(300, 200, 1'b0,   0,  60,   0,  20, "far away - nothing drawn");
	if (drawn != 0) begin errors++; $display("FAIL drew pixels far from the bird"); end

	if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", checks);
	else             $display("TESTS FAILED : %0d errors in %0d checks", errors, checks);
	$finish;
end

endmodule
