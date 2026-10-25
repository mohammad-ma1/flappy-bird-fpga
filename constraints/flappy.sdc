# Flappy Bird timing constraints
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_pll_clocks
derive_clock_uncertainty
# the buttons , switches and the PS2 keyboard are asynchronous inputs ( synchronized in the design )
set_false_path -from [get_ports {KEY[*] SW[*] resetN_pin PS2_CLK PS2_DAT AUDIN[*]}]
set_false_path -to [get_ports {HEX* LEDR[*] AUDOUT[*] OVGA[*]}]
