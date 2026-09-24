# CORDIC Polar TX Microarchitecture

## Decisions to finalize

- Input and output fixed-point scaling
- Phase encoding and wrap convention
- CORDIC iteration count
- Arctangent table representation
- Gain correction method
- Input/output latency and throughput
- `(0, 0)` behavior
- Amplitude overflow and saturation policy
- Reset behavior

## Implemented datapath

The RTL uses an elastic pipeline with one quadrant-correction stage followed by
`ITERATIONS` vectoring stages. Each stage uses signed shift-add arithmetic and
the arctangent lookup table. The ready chain permits one accepted sample per
clock when downstream backpressure is absent, while retaining all in-flight
samples when the output is stalled.

The default implementation has 17 clock cycles of latency for 16 iterations
and an initiation interval of one clock. The final `x` value is multiplied by
the inverse CORDIC gain (`0.607252935`, represented as `16'd39797` in Q0.16),
then saturated to the output amplitude width.

The phase output uses normalized turns and the phase range `[-pi, +pi)`.
Inputs with negative I are reflected before the pipeline and receive the
corresponding `+pi` or `-pi` phase offset.

Add timing diagrams, state transitions, bit-growth analysis, and an error budget before RTL freeze.
