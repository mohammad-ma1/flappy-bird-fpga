// (c) Technion IIT, Department of Electrical Engineering 2025
// Flappy Bird (Controlled Maze) - Lab 1A 044157
// parallax_layers : the moving background ( PARALLAX - a 3D depth effect )
//   three background layers move left at different integer speeds :
//     far  ( stars   ) : 1 pixel every 4 frames
//     mid  ( skyline ) : 1 pixel every 2 frames
//     near ( clouds  ) : 1 pixel every frame
//   the offsets are added to pixelX by flappy_background
//   the layers move once per frame ( startOfFrame ) while runEnable ( frozen on the GAME OVER screen )

module	parallax_layers	(
					input	logic	clk,
					input	logic	resetN,
					input	logic	startOfFrame,     // short pulse every start of frame
					input	logic	runEnable,        // 0 : frozen ( GAME OVER )

					output	logic	[9:0]  farOffset,      // stars   : +1 every 4 frames
					output	logic	[8:0]  midOffset,      // skyline : +1 every 2 frames ( the skyline repeats every 512 )
					output	logic	[7:0]  nearOffset      // clouds  : +1 every frame    ( the clouds repeat every 256 )
);

logic [1:0] frameCount ;      // for the slower layers

always_ff@(posedge clk or negedge resetN)
begin
	if(!resetN) begin
		farOffset  <= '0 ;
		midOffset  <= '0 ;
		nearOffset <= '0 ;
		frameCount <= '0 ;
	end
	else if (startOfFrame && runEnable) begin
		frameCount <= frameCount + 2'd1 ;
		nearOffset <= nearOffset + 8'd1 ;                        // every frame
		if (frameCount[0])
			midOffset <= midOffset + 9'd1 ;                      // every 2 frames
		if (frameCount == 2'd3)
			farOffset <= farOffset + 10'd1 ;                     // every 4 frames
	end
end

endmodule
