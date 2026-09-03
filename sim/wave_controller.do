# ModelSim/Questa wave setup for the tiling controller.
#   vsim -voptargs=+acc tb_tiling_controller
#   do sim/wave_controller.do
#   run -all
#
# Grouped so the boundary-tile mechanism reads top to bottom:
#   position -> remainder -> boundary flag -> handshake

onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {clock / reset}
add wave -noupdate            /tb_tiling_controller/clk
add wave -noupdate            /tb_tiling_controller/rst_n

add wave -noupdate -divider {GEMM shape}
add wave -noupdate -radix unsigned /tb_tiling_controller/M
add wave -noupdate -radix unsigned /tb_tiling_controller/K
add wave -noupdate -radix unsigned /tb_tiling_controller/N

add wave -noupdate -divider {tile position}
add wave -noupdate -radix unsigned /tb_tiling_controller/m_base
add wave -noupdate -radix unsigned /tb_tiling_controller/n_base
add wave -noupdate -radix unsigned /tb_tiling_controller/k_base

add wave -noupdate -divider {REMAINDER - the mechanism}
add wave -noupdate -radix unsigned -color yellow /tb_tiling_controller/rows_valid
add wave -noupdate -radix unsigned -color yellow /tb_tiling_controller/cols_valid
add wave -noupdate -radix unsigned -color yellow /tb_tiling_controller/depth_valid
add wave -noupdate -color red                    /tb_tiling_controller/is_boundary

add wave -noupdate -divider {handshake / control}
add wave -noupdate /tb_tiling_controller/tile_valid
add wave -noupdate /tb_tiling_controller/tile_ack
add wave -noupdate /tb_tiling_controller/clear_acc
add wave -noupdate /tb_tiling_controller/c_tile_done
add wave -noupdate /tb_tiling_controller/busy
add wave -noupdate /tb_tiling_controller/done

add wave -noupdate -divider {internal}
add wave -noupdate -radix unsigned /tb_tiling_controller/dut/state

configure wave -namecolwidth 220
configure wave -valuecolwidth 90
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
