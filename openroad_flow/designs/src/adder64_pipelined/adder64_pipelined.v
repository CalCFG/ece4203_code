module adder64_pipelined (
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire        cin,
    output reg  [63:0] sum,
    output reg         cout
);

//  localparam STAGES = 8;
//  localparam CHUNK = 8;

  localparam STAGES = 64;
  localparam CHUNK = 1;


  // -------------------------------------------------------
  // Stage -1: Input registers
  // -------------------------------------------------------
  reg [63:0] a_r, b_r;
  reg cin_r;

  always @(posedge clk) begin
    if (rst) begin
      a_r   <= '0;
      b_r   <= '0;
      cin_r <= 1'b0;
    end else begin
      a_r   <= a;
      b_r   <= b;
      cin_r <= cin;
    end
  end

  // -------------------------------------------------------
  // Input delay pipeline (shift registers for a_r and b_r)
  // Now STAGES-1 deep, fed from registered inputs
  // -------------------------------------------------------
  reg [63:0] a_d[0:STAGES-2];
  reg [63:0] b_d[0:STAGES-2];

  always @(posedge clk) begin
    if (rst) begin
      for (integer i = 0; i < STAGES - 1; i = i + 1) begin
        a_d[i] <= '0;
        b_d[i] <= '0;
      end
    end else begin
      a_d[0] <= a_r;
      b_d[0] <= b_r;
      for (integer i = 1; i < STAGES - 1; i = i + 1) begin
        a_d[i] <= a_d[i-1];
        b_d[i] <= b_d[i-1];
      end
    end
  end

  // -------------------------------------------------------
  // Carry chain and partial sum registers
  // -------------------------------------------------------
  wire [  CHUNK:0] partial  [0:STAGES-1];
  reg  [CHUNK-1:0] sum_chunk[0:STAGES-1];
  reg              carry    [0:STAGES-1];

  // -------------------------------------------------------
  // Stage 0: uses registered inputs and registered cin
  // -------------------------------------------------------
  assign partial[0] = {1'b0, a_r[CHUNK-1:0]} + {1'b0, b_r[CHUNK-1:0]} + cin_r;

  always @(posedge clk) begin
    if (rst) begin
      sum_chunk[0] <= '0;
      carry[0]     <= 1'b0;
    end else begin
      sum_chunk[0] <= partial[0][CHUNK-1:0];
      carry[0]     <= partial[0][CHUNK];
    end
  end

  // -------------------------------------------------------
  // Stages 1-7: use delayed a_r/b_r, carry from previous stage
  // -------------------------------------------------------
  genvar s;
  generate
    for (s = 1; s < STAGES; s = s + 1) begin : gen_stage
      wire [CHUNK-1:0] a_chunk = a_d[s-1][s*CHUNK+:CHUNK];
      wire [CHUNK-1:0] b_chunk = b_d[s-1][s*CHUNK+:CHUNK];

      assign partial[s] = {1'b0, a_chunk} + {1'b0, b_chunk} + carry[s-1];

      always @(posedge clk) begin
        if (rst) begin
          sum_chunk[s] <= '0;
          carry[s]     <= 1'b0;
        end else begin
          sum_chunk[s] <= partial[s][CHUNK-1:0];
          carry[s]     <= partial[s][CHUNK];
        end
      end
    end
  endgenerate

  // -------------------------------------------------------
  // Sum chunk realignment shift registers
  // chunk[s] needs (STAGES-1-s) additional delay cycles
  // -------------------------------------------------------
  reg [CHUNK-1:0] sum_align[0:STAGES-2][0:STAGES-2];

  always @(posedge clk) begin
    if (rst) begin
      for (integer s = 0; s < STAGES - 1; s = s + 1)
      for (integer d = 0; d < STAGES - 1; d = d + 1) sum_align[s][d] <= '0;
    end else begin
      for (integer s = 0; s < STAGES - 1; s = s + 1) begin
        sum_align[s][0] <= sum_chunk[s];
        for (integer d = 1; d < (STAGES - 1 - s); d = d + 1) sum_align[s][d] <= sum_align[s][d-1];
      end
    end
  end

  // -------------------------------------------------------
  // Output assembly — all chunks aligned to same cycle
  // -------------------------------------------------------

  // Assemble sum into a flat register using generate
  // Each chunk written to its slice independently
  generate
    for (s = 0; s < STAGES; s = s + 1) begin : gen_sum_out
      always @(posedge clk) begin
        if (rst) sum[s*CHUNK+:CHUNK] <= '0;
        else if (s == STAGES - 1)
          // Last stage needs no extra delay
          sum[s*CHUNK+:CHUNK] <= sum_chunk[s];
        else
          // Earlier stages use the last tap of their delay line
          sum[s*CHUNK+:CHUNK] <= sum_align[s][STAGES-2-s];
      end
    end
  endgenerate

  // cout just follows the last carry
  always @(posedge clk) begin
    if (rst) cout <= 1'b0;
    else cout <= carry[STAGES-1];
  end

endmodule
