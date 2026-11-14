# ============================================================
# Zynq PS 最小系统 -> 导出 XSA
# 基于 Vivado 2025.1，器件 xc7z020clg400-2
#
# 用法（二选一）：
#   1. GUI Tcl Console 中：source D:/pyw/vivado_prj/build_hello_world_xsa.tcl
#   2. 命令行批处理：
#      vivado -mode batch -source D:/pyw/vivado_prj/build_hello_world_xsa.tcl
#
# 注意：脚本中 create_project 使用了 -force，
#       如果同名工程已存在，会被删除后重建，请确认路径下没有需要保留的文件。
# ============================================================

# ---------- 工程参数 ----------
set proj_name "hello_world"
set proj_dir  "D:/pyw/vivado_prj/hello_world"
set part      "xc7z020clg400-2"
set bd_name   "system"
set xsa_path  "$proj_dir/vitis/system_wrapper.xsa"

# 如果当前已打开工程，先关闭，避免冲突
if {[current_project -quiet] ne ""} {
    close_project
}

# ---------- 1. 创建 Vivado 工程 ----------
# -force 表示同名工程存在时先删除再重建
create_project $proj_name $proj_dir -part $part -force

# ---------- 2. 创建 Block Design ----------
create_bd_design $bd_name
update_compile_order -fileset sources_1

# ---------- 3. 添加 Zynq PS7 IP ----------
# processing_system7:5.5 是 Zynq-7000 的处理系统 IP
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# ---------- 4. 配置 PS7 ----------
# PCW_EN_CLK0_PORT {0}        : 不启用 FCLK_CLK0 输出
# PCW_EN_RST0_PORT {0}        : 不启用 PS 复位输出
# PCW_UART0_PERIPHERAL_ENABLE : 启用 UART0
# PCW_UART0_UART0_IO          : UART0 映射到 MIO14~15
# PCW_UIPARAM_DDR_PARTNO      : DDR 型号 MT41K256M16 RE-125
# PCW_USE_M_AXI_GP0 {0}       : 不启用 PS 的 M_AXI_GP0 主接口
set_property -dict [list \
    CONFIG.PCW_EN_CLK0_PORT {0} \
    CONFIG.PCW_EN_RST0_PORT {0} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_USE_M_AXI_GP0 {0} \
] [get_bd_cells processing_system7_0]

# ---------- 5. 自动引出 FIXED_IO 和 DDR ----------
# make_external "FIXED_IO, DDR" : 把 FIXED_IO 和 DDR 接口引出为外部端口
# Master/Slave "Disable"        : 不自动创建 AXI 主从连接
# 因为 M_AXI_GP0 被关闭，后面出现“无地址空间匹配”的警告是预期行为
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# ---------- 6. 验证并保存 Block Design ----------
validate_bd_design
save_bd_design

# ---------- 7. 生成 BD 输出产品 ----------
# 包括 HWH、HDL wrapper、仿真/综合用 Verilog 等
set bd_file [get_files "$proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd"]
generate_target all $bd_file

# 导出 IP 用户文件（日志中有，非生成 XSA 必需，但保留）
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet

# ---------- 8. 为 BD 中的 PS7 IP 创建并启动 OOC 综合 ----------
# 这是 IP 的 out-of-context 综合，不是整个工程的顶层综合
set ip_run [create_ip_run [get_files -of_objects [get_fileset sources_1] $bd_file]]
launch_runs $ip_run -jobs 10
# 必须等待 IP 综合完成，否则后续 write_hw_platform 可能拿不到完整结果
wait_on_run $ip_run

# ---------- 9. 导出仿真脚本（可选） ----------
# 这段在日志中存在，但 lib_map_path 依赖本机已编译的仿真库路径。
# 如果换机器或未编译仿真库，可能报错/警告；对生成 XSA 不是必需。
# 如不需要，可整段注释掉。
#
# set sim_lib_map [list \
#     modelsim=$proj_dir/$proj_name.cache/compile_simlib/modelsim \
#     questa=$proj_dir/$proj_name.cache/compile_simlib/questa \
#     riviera=$proj_dir/$proj_name.cache/compile_simlib/riviera \
#     activehdl=$proj_dir/$proj_name.cache/compile_simlib/activehdl]
# export_simulation -lib_map_path $sim_lib_map \
#     -of_objects $bd_file \
#     -directory $proj_dir/$proj_name.ip_user_files/sim_scripts \
#     -ip_user_files_dir $proj_dir/$proj_name.ip_user_files \
#     -ipstatic_source_dir $proj_dir/$proj_name.ip_user_files/ipstatic \
#     -use_ip_compiled_libs -force -quiet

# ---------- 10. 生成 BD Wrapper 并加入工程 ----------
make_wrapper -files $bd_file -top
add_files -norecurse "$proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v"

# 日志中缺少但生成 XSA 前建议补上的两步：
# 设置 wrapper 为顶层，并更新编译顺序
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ---------- 11. 导出 XSA ----------
# -fixed : 导出固定硬件平台（不包含比特流），供 Vitis 创建软件平台
# -force : 覆盖已有 XSA
file mkdir "$proj_dir/vitis"
write_hw_platform -fixed -force -file $xsa_path

puts "=============================================="
puts "XSA 导出完成: $xsa_path"
puts "=============================================="