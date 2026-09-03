# ModelSim/Questa wave setup for the 4x4 systolic array.
#   vsim -voptargs=+acc tb_systolic_array
#   do sim/wave_array.do
#   run -all
#
# Deliberately does NOT add c_flat - a 512-bit bus is unreadable. Individual
# PE accumulators are added instead, which is what you actually want to see.

onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {clock / reset}
add wave -noupdate /tb_systolic_array/clk
add wave -noupdate /tb_systolic_array/rst_n
add wave -noupdate /tb_systolic_array/clear_acc

add wave -noupdate -divider {skewed edge inputs}
add wave -noupdate -radix hexadecimal /tb_systolic_array/a_edge
add wave -noupdate -radix hexadecimal /tb_systolic_array/b_edge

# Corner PEs tell the whole story: (0,0) fills first, (3,3) last.
add wave -noupdate -divider {PE(0,0) - first to fill}
add wave -noupdate -radix decimal /tb_systolic_array/dut/g_row[0]/g_col[0]/u_pe/a_in
add wave -noupdate -radix decimal /tb_systolic_array/dut/g_row[0]/g_col[0]/u_pe/b_in
add wave -noupdate -radix decimal -color yellow \
    /tb_systolic_array/dut/g_row[0]/g_col[0]/u_pe/acc_out

add wave -noupdate -divider {PE(0,3) - right edge}
add wave -noupdate -radix decimal /tb_systolic_array/dut/g_row[0]/g_col[3]/u_pe/a_in
add wave -noupdate -radix decimal -color yellow \
    /tb_systolic_array/dut/g_row[0]/g_col[3]/u_pe/acc_out

add wave -noupdate -divider {PE(3,3) - last to fill (pipeline depth)}
add wave -noupdate -radix decimal /tb_systolic_array/dut/g_row[3]/g_col[3]/u_pe/a_in
add wave -noupdate -radix decimal /tb_systolic_array/dut/g_row[3]/g_col[3]/u_pe/b_in
add wave -noupdate -radix decimal -color yellow \
    /tb_systolic_array/dut/g_row[3]/g_col[3]/u_pe/acc_out

configure wave -namecolwidth 300
configure wave -valuecolwidth 80
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
