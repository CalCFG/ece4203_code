`timescale 1ns/1ps

module tb_adder64_pipelined;

    // -------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------
    reg         clk, rst;
    reg  [63:0] a, b;
    reg         cin;
    wire [63:0] sum;
    wire        cout;

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    adder64_pipelined dut (
        .clk  (clk),
        .rst  (rst),
        .a    (a),
        .b    (b),
        .cin  (cin),
        .sum  (sum),
        .cout (cout)
    );

    // -------------------------------------------------------
    // Clock
    // -------------------------------------------------------
    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    // Reference model — delay line to match 9-cycle latency
    // -------------------------------------------------------
    localparam LATENCY = 10;

    reg [63:0] a_delay   [0:LATENCY-1];
    reg [63:0] b_delay   [0:LATENCY-1];
    reg        cin_delay [0:LATENCY-1];

    wire [64:0] expected = {1'b0, a_delay[LATENCY-1]} 
                         + {1'b0, b_delay[LATENCY-1]} 
                         + cin_delay[LATENCY-1];

    integer i;
    always @(posedge clk) begin
        a_delay[0]   <= a;
        b_delay[0]   <= b;
        cin_delay[0] <= cin;
        for (i = 1; i < LATENCY; i = i + 1) begin
            a_delay[i]   <= a_delay[i-1];
            b_delay[i]   <= b_delay[i-1];
            cin_delay[i] <= cin_delay[i-1];
        end
    end

    // -------------------------------------------------------
    // Error tracking
    // -------------------------------------------------------
    integer pass_count, fail_count, cycle_count;

    task check_output;
        input [63:0] got_sum;
        input        got_cout;
        input [63:0] exp_sum;
        input        exp_cout;
        input [63:0] src_a;
        input [63:0] src_b;
        input        src_cin;
        begin
            if (got_sum !== exp_sum || got_cout !== exp_cout) begin
                $display("FAIL cycle=%0d | a=%h b=%h cin=%b | expected sum=%h cout=%b | got sum=%h cout=%b",
                    cycle_count, src_a, src_b, src_cin,
                    exp_sum, exp_cout,
                    got_sum, got_cout);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------
    // Stimulus + checking
    // -------------------------------------------------------
    integer seed;
    reg [64:0] ref_full;

    initial begin
        // Init
        clk        = 0;
        rst        = 1;
        a          = '0;
        b          = '0;
        cin        = 0;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        seed       = 42;

        // Reset for a few cycles
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 0;

        // -------------------------------------------------------
        // Phase 1: corner cases — drive on negedge, check on posedge
        // -------------------------------------------------------
        $display("--- Corner cases ---");

        // Zero + Zero
        @(negedge clk) a = 64'h0; b = 64'h0; cin = 0;
        // Max + 0
        @(negedge clk) a = 64'hFFFFFFFFFFFFFFFF; b = 64'h0; cin = 0;
        // Max + 1 (overflow)
        @(negedge clk) a = 64'hFFFFFFFFFFFFFFFF; b = 64'h1; cin = 0;
        // Max + Max
        @(negedge clk) a = 64'hFFFFFFFFFFFFFFFF; b = 64'hFFFFFFFFFFFFFFFF; cin = 0;
        // Max + Max + cin
        @(negedge clk) a = 64'hFFFFFFFFFFFFFFFF; b = 64'hFFFFFFFFFFFFFFFF; cin = 1;
        // Carry chain stress: all 0x55 + all 0xAA
        @(negedge clk) a = 64'h5555555555555555; b = 64'hAAAAAAAAAAAAAAAA; cin = 0;
        // Carry chain stress + cin
        @(negedge clk) a = 64'h5555555555555555; b = 64'hAAAAAAAAAAAAAAAA; cin = 1;
        // LSB only
        @(negedge clk) a = 64'h1; b = 64'h0; cin = 1;
        // MSB only
        @(negedge clk) a = 64'h8000000000000000; b = 64'h8000000000000000; cin = 0;
        // Chunk boundary stress: carry must propagate across all 8 chunks
        @(negedge clk) a = 64'h00FFFFFFFFFFFFFF; b = 64'h0000000000000001; cin = 0;

        // -------------------------------------------------------
        // Phase 2: random vectors
        // -------------------------------------------------------
        $display("--- Random vectors ---");
        repeat (200) begin
            @(negedge clk) begin
                a   = {$random(seed), $random(seed)};
                b   = {$random(seed), $random(seed)};
                cin = $random(seed) & 1;
            end
        end

        // Flush pipeline — keep last inputs stable for LATENCY cycles
        // so all in-flight results drain out and get checked
        repeat (LATENCY) @(negedge clk);

        // -------------------------------------------------------
        // Report
        // -------------------------------------------------------
        $display("-----------------------------------");
        $display("PASSED: %0d  FAILED: %0d  TOTAL: %0d",
                  pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILURES DETECTED");
        $display("-----------------------------------");
        $finish;
    end

    // -------------------------------------------------------
    // Checker — runs every cycle after latency has elapsed
    // Skips cycles still in reset or filling the pipeline
    // -------------------------------------------------------
    reg [7:0] startup_count;

    initial startup_count = 0;

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;

        // Count cycles after reset deasserts
        if (!rst) begin
            if (startup_count < LATENCY)
                startup_count <= startup_count + 1;
        end else begin
            startup_count <= 0;
        end

        // Only check once pipeline is full
        if (!rst && startup_count == LATENCY) begin
            check_output(
                sum,  cout,
                expected[63:0], expected[64],
                a_delay[LATENCY-1], b_delay[LATENCY-1], cin_delay[LATENCY-1]
            );
        end
    end

    // -------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("tb_adder64_pipelined.vcd");
        $dumpvars(0, tb_adder64_pipelined);
    end

endmodule
