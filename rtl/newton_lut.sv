`include "defs.svh"

module newton_lut(
    input logic parity,
    input logic [`LUTBITS-1:0] mantissa,
    output dword_t val
);

    dword_t lut [1:0][`LUTSIZE-1:0];
    initial $readmemh("newton_lut.hex", lut);

    assign val = lut[parity][mantissa];

endmodule
