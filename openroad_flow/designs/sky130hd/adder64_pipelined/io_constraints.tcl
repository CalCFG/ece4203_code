# io_constraints.tcl
# 64-bit adder: inputs a[63:0], b[63:0], cin; outputs sum[63:0], cout
# Edges: 0=bottom, 1=right, 2=top, 3=left

# a[0:31]  on the left edge, evenly spread top half
set_io_pin_constraint -pin_names {a[0] a[1] a[2] a[3] a[4] a[5] a[6] a[7]
                                   a[8] a[9] a[10] a[11] a[12] a[13] a[14] a[15]
                                   a[16] a[17] a[18] a[19] a[20] a[21] a[22] a[23]
                                   a[24] a[25] a[26] a[27] a[28] a[29] a[30] a[31]} \
                       -region left:10-60

# a[32:63] on the left edge, bottom half
set_io_pin_constraint -pin_names {a[32] a[33] a[34] a[35] a[36] a[37] a[38] a[39]
                                   a[40] a[41] a[42] a[43] a[44] a[45] a[46] a[47]
                                   a[48] a[49] a[50] a[51] a[52] a[53] a[54] a[55]
                                   a[56] a[57] a[58] a[59] a[60] a[61] a[62] a[63]} \
                       -region left:60-110

# b[0:31]  on the bottom edge, left half
set_io_pin_constraint -pin_names {b[0] b[1] b[2] b[3] b[4] b[5] b[6] b[7]
                                   b[8] b[9] b[10] b[11] b[12] b[13] b[14] b[15]
                                   b[16] b[17] b[18] b[19] b[20] b[21] b[22] b[23]
                                   b[24] b[25] b[26] b[27] b[28] b[29] b[30] b[31]} \
                       -region bottom:10-60

# b[32:63] on the bottom edge, right half
set_io_pin_constraint -pin_names {b[32] b[33] b[34] b[35] b[36] b[37] b[38] b[39]
                                   b[40] b[41] b[42] b[43] b[44] b[45] b[46] b[47]
                                   b[48] b[49] b[50] b[51] b[52] b[53] b[54] b[55]
                                   b[56] b[57] b[58] b[59] b[60] b[61] b[62] b[63]} \
                       -region bottom:60-110

# cin on the bottom edge, far right corner
set_io_pin_constraint -pin_names {cin} \
                       -region bottom:110-120

# sum[0:31] on the right edge, top half
set_io_pin_constraint -pin_names {sum[0] sum[1] sum[2] sum[3] sum[4] sum[5] sum[6] sum[7]
                                   sum[8] sum[9] sum[10] sum[11] sum[12] sum[13] sum[14] sum[15]
                                   sum[16] sum[17] sum[18] sum[19] sum[20] sum[21] sum[22] sum[23]
                                   sum[24] sum[25] sum[26] sum[27] sum[28] sum[29] sum[30] sum[31]} \
                       -region right:10-60

# sum[32:63] on the right edge, bottom half
set_io_pin_constraint -pin_names {sum[32] sum[33] sum[34] sum[35] sum[36] sum[37] sum[38] sum[39]
                                   sum[40] sum[41] sum[42] sum[43] sum[44] sum[45] sum[46] sum[47]
                                   sum[48] sum[49] sum[50] sum[51] sum[52] sum[53] sum[54] sum[55]
                                   sum[56] sum[57] sum[58] sum[59] sum[60] sum[61] sum[62] sum[63]} \
                       -region right:60-110

# cout on the top edge
set_io_pin_constraint -pin_names {cout} \
                       -region top:50-60

# Apply pin placement with sky130hd metal layers
#place_pins \
#  -hor_layers metal3 \
#  -ver_layers metal2 \
#  -corner_avoidance 1 \
#  -min_distance 0.5
