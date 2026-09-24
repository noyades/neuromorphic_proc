module cordic_polar_tx_tb;
        localparam int INPUT_WIDTH = 16;
        localparam int OUTPUT_WIDTH = 16;
        localparam int ITERATIONS = 16;
        localparam int AMPLITUDE_TOLERANCE = 4;
        localparam int PHASE_TOLERANCE = 8;
        localparam real PI = 3.14159265358979323846;

        logic clk = 1'b0;
        logic rst_n = 1'b0;
        logic in_valid;
        logic in_ready;
        logic signed [INPUT_WIDTH-1:0] i_in;
        logic signed [INPUT_WIDTH-1:0] q_in;
        logic out_valid;
        logic out_ready;
        logic [OUTPUT_WIDTH-1:0] amplitude_out;
        logic signed [OUTPUT_WIDTH-1:0] phase_out;

        int checks;
        int errors;
        int sent;
        int received;
        int unsigned random_seed = 32'h1A2B3C4D;

        typedef struct {
            int expected_amplitude;
            int expected_phase;
            int sample_i;
            int sample_q;
        } expected_result_t;
        expected_result_t expected_queue[$];

        cordic_polar_tx #(
            .INPUT_WIDTH(INPUT_WIDTH),
            .OUTPUT_WIDTH(OUTPUT_WIDTH),
            .ITERATIONS(ITERATIONS)
        ) dut (.*);

        always #5 clk = ~clk;

        function automatic int wrap_phase(input int phase);
            int wrapped_phase;
            begin
                wrapped_phase = phase;
                while (wrapped_phase > 32767)
                    wrapped_phase = wrapped_phase - 65536;
                while (wrapped_phase < -32768)
                    wrapped_phase = wrapped_phase + 65536;
                return wrapped_phase;
            end
        endfunction

        function automatic int reference_amplitude(input int sample_i, input int sample_q);
            real magnitude;
            begin
                magnitude = $sqrt((sample_i * sample_i) + (sample_q * sample_q));
                if (magnitude >= 65535.0)
                    return 65535;
                return $rtoi(magnitude);
            end
        endfunction

        function automatic int reference_phase(input int sample_i, input int sample_q);
            real phase_turns;
            int phase_code;
            begin
                if ((sample_i == 0) && (sample_q == 0))
                    return 0;
                phase_turns = $atan2(sample_q, sample_i) / (2.0 * PI);
                phase_code = $rtoi(phase_turns * 65536.0);
                return wrap_phase(phase_code);
            end
        endfunction

        function automatic int random_sample;
            int unsigned random_bits;
            begin
                random_bits = $urandom(random_seed);
                return $signed(random_bits[15:0]);
            end
        endfunction

        task automatic enqueue_sample(input int sample_i, input int sample_q);
            expected_result_t expected;
            begin
                @(negedge clk);
                while (!in_ready)
                    @(negedge clk);

                i_in <= sample_i;
                q_in <= sample_q;
                in_valid <= 1'b1;
                expected.sample_i = sample_i;
                expected.sample_q = sample_q;
                expected.expected_amplitude = reference_amplitude(sample_i, sample_q);
                expected.expected_phase = reference_phase(sample_i, sample_q);
                expected_queue.push_back(expected);
                sent = sent + 1;

                @(negedge clk);
                in_valid <= 1'b0;
            end
        endtask

        task automatic check_output;
            expected_result_t expected;
            int actual_phase;
            int amplitude_error;
            int phase_error;
            begin
                if (out_valid && out_ready) begin
                    if (expected_queue.size() == 0) begin
                        $error("Unexpected output at time %0t", $time);
                        errors = errors + 1;
                    end else begin
                        expected = expected_queue.pop_front();
                        actual_phase = $signed(phase_out);
                        amplitude_error = $unsigned(amplitude_out) - expected.expected_amplitude;
                        phase_error = actual_phase - expected.expected_phase;
                        if (amplitude_error < 0)
                            amplitude_error = -amplitude_error;
                        if (phase_error < 0)
                            phase_error = -phase_error;
                        if (phase_error > 32768)
                            phase_error = 65536 - phase_error;
                        checks = checks + 1;
                        if ((amplitude_error > AMPLITUDE_TOLERANCE) ||
                            (phase_error > PHASE_TOLERANCE)) begin
                            $error("Mismatch I=%0d Q=%0d: got A=%0d P=%0d, expected A=%0d P=%0d",
                                expected.sample_i, expected.sample_q, $unsigned(amplitude_out),
                                actual_phase, expected.expected_amplitude, expected.expected_phase);
                            errors = errors + 1;
                        end
                    end
                    received = received + 1;
                end
            end
        endtask

        always @(posedge clk) begin
            if (rst_n)
                check_output();
        end

        property output_stable_under_backpressure;
            @(posedge clk) disable iff (!rst_n)
                out_valid && !out_ready |=> out_valid && $stable(amplitude_out) && $stable(phase_out);
        endproperty
        assert property (output_stable_under_backpressure)
            else $error("Output changed while stalled at time %0t", $time);

        initial begin
            in_valid = 1'b0;
            out_ready = 1'b0;
            i_in = '0;
            q_in = '0;
            checks = 0;
            errors = 0;
            sent = 0;
            received = 0;

            repeat (3) @(posedge clk);
            rst_n <= 1'b1;

            enqueue_sample(0, 0);
            enqueue_sample(32767, 0);
            enqueue_sample(-32768, 0);
            enqueue_sample(0, 32767);
            enqueue_sample(0, -32768);
            enqueue_sample(23170, 23170);
            enqueue_sample(-23170, 23170);
            enqueue_sample(-23170, -23170);
            enqueue_sample(23170, -23170);
            enqueue_sample(1, 1);
            enqueue_sample(-1, 1);
            enqueue_sample(-1, -1);
            enqueue_sample(1, -1);

            repeat (32) begin
                enqueue_sample(random_sample(), random_sample());
            end

            while (expected_queue.size() != 0) begin
                @(negedge clk);
                out_ready <= ($urandom(random_seed) % 4) != 0;
            end
            repeat (3) @(negedge clk);
            out_ready <= 1'b1;
            @(posedge clk);

            if ((errors == 0) && (checks == sent) && (received == sent))
                $display("CORDIC PASS: %0d samples checked", checks);
            else
                $fatal(1, "CORDIC FAIL: sent=%0d received=%0d checks=%0d errors=%0d",
                    sent, received, checks, errors);
            $finish;
        end

        initial begin
            #200000;
            $fatal(1, "CORDIC testbench timeout");
        end
endmodule
