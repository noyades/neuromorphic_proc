module cordic_polar_tx #(
    parameter int INPUT_WIDTH = 16,
    parameter int OUTPUT_WIDTH = 16,
    parameter int ITERATIONS = 16
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         in_valid,
    output logic                         in_ready,
    input  logic signed [INPUT_WIDTH-1:0] i_in,
    input  logic signed [INPUT_WIDTH-1:0] q_in,
    output logic                         out_valid,
    input  logic                         out_ready,
    output logic        [OUTPUT_WIDTH-1:0] amplitude_out,
    output logic signed [OUTPUT_WIDTH-1:0] phase_out
);
    localparam int DATA_WIDTH = INPUT_WIDTH + 3;
    localparam int PRODUCT_WIDTH = DATA_WIDTH + 16;
    localparam logic [15:0] CORDIC_GAIN_INVERSE = 16'd39797;

    logic [ITERATIONS:0] stage_valid;
    logic [ITERATIONS:0] stage_ready;
    logic signed [DATA_WIDTH-1:0] x_pipe [0:ITERATIONS];
    logic signed [DATA_WIDTH-1:0] y_pipe [0:ITERATIONS];
    logic signed [OUTPUT_WIDTH-1:0] z_pipe [0:ITERATIONS];
    logic signed [DATA_WIDTH-1:0] stage_x;
    logic signed [DATA_WIDTH-1:0] stage_y;
    logic signed [OUTPUT_WIDTH-1:0] stage_z;
    logic signed [PRODUCT_WIDTH-1:0] final_gain_product;
    integer stage_index;

    function automatic logic signed [OUTPUT_WIDTH-1:0] atan_lut(input int index);
        begin
            case (index)
                0:  atan_lut = $signed(16'sh2000);
                1:  atan_lut = $signed(16'sh12E4);
                2:  atan_lut = $signed(16'sh09FB);
                3:  atan_lut = $signed(16'sh0511);
                4:  atan_lut = $signed(16'sh028B);
                5:  atan_lut = $signed(16'sh0145);
                6:  atan_lut = $signed(16'sh00A3);
                7:  atan_lut = $signed(16'sh0051);
                8:  atan_lut = $signed(16'sh0029);
                9:  atan_lut = $signed(16'sh0014);
                10: atan_lut = $signed(16'sh000A);
                11: atan_lut = $signed(16'sh0005);
                12: atan_lut = $signed(16'sh0003);
                13: atan_lut = $signed(16'sh0001);
                14: atan_lut = $signed(16'sh0001);
                15: atan_lut = $signed(16'sh0000);
                default: atan_lut = '0;
            endcase
        end
    endfunction

    assign out_valid = stage_valid[ITERATIONS];
    assign in_ready = stage_ready[0];
    assign stage_ready[ITERATIONS] = !stage_valid[ITERATIONS] || out_ready;

    always_comb begin
        for (stage_index = ITERATIONS - 1; stage_index >= 0; stage_index = stage_index - 1)
            stage_ready[stage_index] = !stage_valid[stage_index] || stage_ready[stage_index + 1];
    end

    assign amplitude_out = (final_gain_product >>> 16) < 0 ?
        '0 : ((final_gain_product >>> 16) > $signed({1'b0, {OUTPUT_WIDTH{1'b1}}}) ?
        {OUTPUT_WIDTH{1'b1}} : (final_gain_product >>> 16));
    assign final_gain_product = x_pipe[ITERATIONS] * $signed({1'b0, CORDIC_GAIN_INVERSE});
    assign phase_out = z_pipe[ITERATIONS];

    always_ff @(posedge clk or negedge rst_n) begin : cordic_pipeline
        logic signed [DATA_WIDTH-1:0] next_x;
        logic signed [DATA_WIDTH-1:0] next_y;
        logic signed [OUTPUT_WIDTH-1:0] next_z;

        if (!rst_n) begin
            stage_valid <= '0;
            for (stage_index = 0; stage_index <= ITERATIONS; stage_index = stage_index + 1) begin
                x_pipe[stage_index] <= '0;
                y_pipe[stage_index] <= '0;
                z_pipe[stage_index] <= '0;
            end
        end else begin
            for (stage_index = 0; stage_index <= ITERATIONS; stage_index = stage_index + 1) begin
                if (stage_ready[stage_index]) begin
                    if (stage_index == 0) begin
                        stage_valid[0] <= in_valid;
                        if (in_valid) begin
                            if (i_in < 0) begin
                                x_pipe[0] <= -$signed(i_in);
                                y_pipe[0] <= -$signed(q_in);
                                if (q_in >= 0)
                                    z_pipe[0] <= $signed(16'sh8000);
                                else
                                    z_pipe[0] <= -$signed(16'sh8000);
                            end else begin
                                x_pipe[0] <= $signed(i_in);
                                y_pipe[0] <= $signed(q_in);
                                z_pipe[0] <= '0;
                            end
                        end
                    end else begin
                        stage_valid[stage_index] <= stage_valid[stage_index - 1];
                        if (stage_valid[stage_index - 1]) begin
                            if (y_pipe[stage_index - 1] >= 0) begin
                                next_x = x_pipe[stage_index - 1] +
                                    (y_pipe[stage_index - 1] >>> (stage_index - 1));
                                next_y = y_pipe[stage_index - 1] -
                                    (x_pipe[stage_index - 1] >>> (stage_index - 1));
                                next_z = z_pipe[stage_index - 1] + atan_lut(stage_index - 1);
                            end else begin
                                next_x = x_pipe[stage_index - 1] -
                                    (y_pipe[stage_index - 1] >>> (stage_index - 1));
                                next_y = y_pipe[stage_index - 1] +
                                    (x_pipe[stage_index - 1] >>> (stage_index - 1));
                                next_z = z_pipe[stage_index - 1] - atan_lut(stage_index - 1);
                            end
                            x_pipe[stage_index] <= next_x;
                            y_pipe[stage_index] <= next_y;
                            z_pipe[stage_index] <= next_z;
                        end
                    end
                end
            end
        end
    end

    `ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && out_valid && !out_ready) begin
            assert ($stable(amplitude_out));
            assert ($stable(phase_out));
            assert ($stable(out_valid));
        end
    end
    `endif
endmodule
