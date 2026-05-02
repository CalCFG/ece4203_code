// ECE4203
//
// Both inputs AND outputs are registered, giving the canonical
// two-FF pipeline stage:
//
//   clk ──► [Input FFs] ──► adder carry chain ──► [Output FFs]
//            (stage 1)        (combinational)        (stage 2)
//
// The setup-time critical path is entirely inside this module:
//
//   clk ──[launch: input FF Q] ──► carry chain ──► [capture: output FF D]
//           ▲                                                  ▲
//           └──────────────── clock period budget ─────────────┘
//
// There is no ambiguity about input arrival times or output
// load — synthesis and STA see a perfectly constrained path.
//
// Latency: 2 clock cycles (1 cycle input reg + 1 cycle output reg)
//
// Ports
//   clk    rising-edge clock
//   rst_n  synchronous active-low reset (clears all registers)
//   a, b   addend inputs   (WIDTH bits)
//   cin    carry-in input
//   sum    registered sum  (WIDTH bits)
//   cout   registered carry-out

`timescale 1ns/1ps

module registered_adder #(
    parameter WIDTH = 64
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    input  wire              cin,
    output reg  [WIDTH-1:0]  sum,
    output reg               cout
//    output wire [WIDTH:0]    result // for probing
);

    // -------------------------------------------------------
    // Stage 1 — Input registers
    // Capture a, b, cin on the rising clock edge.
    // The adder combinational logic operates on these stable,
    // registered values — not on the raw input ports.
    // -------------------------------------------------------
    reg  [WIDTH-1:0] a_r, b_r;
    reg              cin_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r   <= {WIDTH{1'b0}};
            b_r   <= {WIDTH{1'b0}};
            cin_r <= 1'b0;
        end else begin
            a_r   <= a;
            b_r   <= b;
            cin_r <= cin;
        end
    end

    // -------------------------------------------------------
    // Combinational adder
    // Operates on the registered inputs a_r, b_r, cin_r.
    // The extra bit on result captures carry-out.
    // -------------------------------------------------------

    assign result = {1'b0, a_r} + {1'b0, b_r} + {{WIDTH{1'b0}}, cin_r};

    // -------------------------------------------------------
    // Stage 2 — Output registers
    // Capture the combinational result on the next rising edge.
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum  <= {WIDTH{1'b0}};
            cout <= 1'b0;
        end else begin
            sum  <= result[WIDTH-1:0];
            cout <= result[WIDTH];
        end
    end

endmodule
