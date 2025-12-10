`timescale 1ns / 1ps

module UART_Periph (
    // global signal
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    input  logic [ 3:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    input  logic        PENABLE,
    input  logic        PSEL,
    output logic [31:0] PRDATA,
    output logic        PREADY,

    input  logic rx,
    output logic tx
);

    logic empty_TX, full_TX;
    logic empty_RX, full_RX;
    logic we_TX, re_RX;
    logic tick;
    logic [7:0] wdata_TX, rdata_TX;
    logic [7:0] wdata_RX, rdata_RX;
    logic rx_done;
    logic o_tx_done;

    APB_SlaveIntf_UART U_APB_SlaveInterf_UART(
        .*,
        .USR({full_RX, empty_TX, !full_TX, !empty_RX}),
        .UWD(wdata_TX),
        .URD(rdata_RX)
    );

    fifo U_FIFO_TX (
        .clk(PCLK),
        .reset(PRESET),
        .we(we_TX),
        .re(!empty_TX & !o_tx_done),
        .wdata(wdata_TX),
        .rdata(rdata_TX),
        .empty(empty_TX),
        .full(full_TX)
    );

    fifo U_FIFO_RX (
        .clk(PCLK),
        .reset(PRESET),
        .we(rx_done),
        .re(re_RX),
        .wdata(wdata_RX),
        .rdata(rdata_RX),
        .empty(empty_RX),
        .full(full_RX)
    );

    uart_rx U_RX (
        .*,
        .clk(PCLK),
        .rst(PRESET),
        .rx_data(wdata_RX)
    );

    uart_tx U_TX (
        .*,
        .clk(PCLK),
        .rst(PRESET),
        .i_data(rdata_TX),
        .tx_start(!empty_TX)
    );

    baud_tick_gen U_BAUD_TICK_GEN (
        .clk(PCLK),
        .rst(PRESET),
        .baud_tick(tick)
    );
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module APB_SlaveIntf_UART (
    // global signal
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    input  logic [ 3:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    input  logic        PENABLE,
    input  logic        PSEL,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    // internal signals
    input  logic [ 3:0] USR,
    output logic [ 7:0] UWD,
    input  logic [ 7:0] URD,
    output logic        we_TX,
    output logic        re_RX
);

    logic [31:0] slv_reg0, slv_reg1, slv_reg2, slv_reg3;
    logic [31:0] slv_reg1_next, slv_reg2_next;

    logic we_reg, we_next;
    logic re_reg, re_next;
    logic [31:0] PRDATA_reg, PRDATA_next;
    logic PREADY_reg, PREADY_next;

    assign we_TX = we_reg;
    assign re_RX = re_reg;

    typedef enum {
        IDLE,
        READ,
        WRITE
    } state_e;

    state_e state_reg, state_next;

    assign slv_reg0[3:0] = USR;
    assign ULS = slv_reg1;
    assign UWD = slv_reg2[7:0];
    assign slv_reg3[7:0] = URD;

    assign PRDATA = PRDATA_reg;
    assign PREADY = PREADY_reg;

    always_ff @(posedge PCLK, posedge PRESET) begin
        if (PRESET) begin
            slv_reg0[31:4] <=0; //USR 
            slv_reg1 <=0; //USR_RX
            slv_reg3[31:8] <=0;
            slv_reg2 <=0;
            state_reg <= IDLE;
            we_reg    <= 0;
            re_reg    <= 0;
            PRDATA_reg <= 32'bx;
            PREADY_reg <= 1'b0;
        end else begin
            slv_reg1 <= slv_reg1_next;
            slv_reg2  <= slv_reg2_next;
            state_reg <= state_next;
            we_reg    <= we_next;
            re_reg    <= re_next;
            PRDATA_reg <= PRDATA_next;
            PREADY_reg <= PREADY_next;
        end
    end

    always_comb begin
        state_next = state_reg;
        slv_reg1_next = slv_reg1;
        slv_reg2_next = slv_reg2;
        we_next = we_reg;
        re_next = re_reg;
        PRDATA_next = PRDATA_reg;
        PREADY_next = PREADY_reg;

        case (state_reg)
            IDLE: begin
                PREADY_next = 1'b0;
                if (PSEL && PENABLE) begin
                    if (PWRITE) begin
                        state_next = WRITE;
                        we_next = 1'b1;
                        re_next = 1'b0;
                        PREADY_next = 1'b1;
                        case (PADDR[3:2])
                            2'd0: ;
                            2'd1: slv_reg1_next = PWDATA;
                            2'd2: begin
                                slv_reg2_next = PWDATA;
                            end

                        endcase
                    end else begin
                        state_next = READ;
                        PREADY_next = 1'b1;
                        we_next = 1'b0;
                        case (PADDR[3:2])
                            2'd0: begin
                                PRDATA_next = slv_reg0;
                                re_next = 1'b0;
                            end
                            2'd1: begin
                                PRDATA_next = slv_reg1;
                                re_next = 1'b0;
                            end
                            2'd2: begin
                                PRDATA_next = slv_reg2;
                                re_next = 1'b0;
                            end
                            2'd3: begin
                                PRDATA_next = slv_reg3;
                                re_next = 1'b1;
                            end
                        endcase
                    end
                end
            end

            READ: begin
                re_next = 1'b0;
                we_next = 1'b0;
                PREADY_next = 1'b0;
                state_next = IDLE;
            end
            WRITE: begin
                we_next = 1'b0;
                re_next = 1'b0;
                state_next = IDLE;
                PREADY_next = 1'b0;
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo (
    input  logic       clk,
    input  logic       reset,
    input  logic       we,
    input  logic       re,
    input  logic [7:0] wdata,
    output logic [7:0] rdata,
    output logic       empty,
    output logic       full
);
    logic [1:0] wptr, rptr;

    fifo_ram U_FIFO_RAM (
        .clk  (clk),
        .we   (!full & we),
        .wdata(wdata),
        .waddr(wptr),
        .raddr(rptr),
        .rdata(rdata)
    );
    fifo_CU U_FIFO_CU (.*);

endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo_ram (
    input  logic       clk,
    input  logic       we,
    input  logic [7:0] wdata,
    input  logic [1:0] waddr,
    input  logic [1:0] raddr,
    output logic [7:0] rdata
);

    logic [7:0] mem[0:3];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];

endmodule

////////////////////////////////////////////////////////////////////////////////////////

module fifo_CU (
    input  logic       clk,
    input  logic       reset,
    input  logic       we,
    input  logic       re,
    output logic       empty,
    output logic       full,
    output logic [1:0] rptr,
    output logic [1:0] wptr
);

    logic [1:0] wptr_reg, wptr_next;
    logic [1:0] rptr_reg, rptr_next;
    logic empty_reg, empty_next;
    logic full_reg, full_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;

    assign empty = empty_reg;
    assign full  = full_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            empty_reg <= 1'b1;
            full_reg  <= 0;
        end else begin
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            empty_reg <= empty_next;
            full_reg  <= full_next;
        end
    end

    logic [1:0] fifo_state;
    assign fifo_state = {we, re};

    localparam READ = 2'b01, WRITE = 2'b10, READ_WRITE = 2'b11;

    always_comb begin
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        empty_next = empty_reg;
        full_next  = full_reg;

        case (fifo_state)
            READ: begin
                if (!empty_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                    if (wptr_next == rptr_next) begin
                        empty_next = 1'b1;
                    end
                end
            end
            WRITE: begin
                if (!full_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr_next) begin
                        full_next = 1'b1;
                    end
                end
            end
            READ_WRITE: begin
                if (full_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else if (empty_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else begin
                    rptr_next = rptr_reg + 1;
                    wptr_next = wptr_reg + 1;

                end
            end
        endcase
    end

endmodule

////////////////////////////////////////////////////////////////////////////////////////

module uart_rx (
    input logic clk,
    input logic rst,
    input logic rx,
    input logic tick,
    output logic [7:0] rx_data,
    output logic rx_done
);
    typedef enum logic [1:0] {
        IDLE  = 0,
        START = 1,
        DATA  = 2,
        STOP  = 3
    } state_t;

    state_t rx_state, rx_next;
    logic [7:0] rx_out_reg, rx_out_next;
    logic [3:0] tick_cnt_reg, tick_cnt_next;
    logic [3:0] data_cnt_reg, data_cnt_next;
    logic rx_done_reg, rx_done_next;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= IDLE;
            rx_done_reg <= 1'b0;
            rx_out_reg <= 8'bx;
            data_cnt_reg <= 0;
            tick_cnt_reg <= 0;
        end else begin
            rx_state <= rx_next;
            rx_out_reg <= rx_out_next;
            data_cnt_reg <= data_cnt_next;
            rx_done_reg <= rx_done_next;
            tick_cnt_reg <= tick_cnt_next;
        end
    end

    assign rx_done = rx_done_reg;
    assign rx_data = rx_out_reg;

    always_comb begin
        rx_out_next = rx_out_reg;
        rx_next = rx_state;
        data_cnt_next = data_cnt_reg;
        rx_done_next = 1'b0;
        tick_cnt_next = tick_cnt_reg;

        case (rx_state)
            IDLE: begin
                if (!rx) rx_next = START;
            end
            START: begin
                if (tick) begin
                    if (tick_cnt_reg == 7) begin
                        tick_cnt_next = 0;
                        rx_next = DATA;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                if (tick) begin
                    if (tick_cnt_reg == 15) begin
                        rx_out_next[data_cnt_reg] = rx;
                        tick_cnt_next = 0;
                        if (data_cnt_reg < 7) begin
                            data_cnt_next = data_cnt_reg + 1;
                        end else begin
                            data_cnt_next = 0;
                            rx_next = STOP;
                        end
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                if (tick) begin
                    if (tick_cnt_reg == 15) begin
                        rx_done_next = 1'b1;
                        tick_cnt_next = 0;
                        rx_next = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module uart_tx (
    input logic clk,
    input logic rst,
    input logic [7:0] i_data,
    input logic tick,
    input logic tx_start,
    output logic tx,
    output logic o_tx_done
);
    typedef enum logic [2:0] {
        IDLE  = 0,
        SEND  = 1,
        START = 2,
        DATA  = 3,
        STOP  = 4
    } state_t;

    state_t state, next;
    logic tx_reg, tx_next;
    logic tx_done_reg, tx_done_next;
    logic [3:0] bit_count_reg, bit_count_next;
    logic [3:0] tick_count_reg, tick_count_next;
    logic [7:0] temp_data_reg, temp_data_next;

    assign tx = tx_reg;
    assign o_tx_done = tx_done_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_reg <= 1'b1;
            tx_done_reg <= 0;
            bit_count_reg <= 0;
            tick_count_reg <= 0;
            temp_data_reg <= 0;
        end else begin
            state <= next;
            tx_reg <= tx_next;
            tx_done_reg <= tx_done_next;
            bit_count_reg <= bit_count_next;
            tick_count_reg <= tick_count_next;
            temp_data_reg <= temp_data_next;
        end
    end

    always_comb begin
        next = state;
        tx_next = tx_reg;
        tx_done_next = tx_done_reg;
        bit_count_next = bit_count_reg;
        tick_count_next = tick_count_reg;
        temp_data_next = temp_data_reg;

        case (state)
            IDLE: begin
                tx_next = 1'b1;
                tx_done_next = 1'b0;
                if (tx_start) begin
                    next = SEND;
                    temp_data_next = i_data;
                end
            end
            SEND: begin
                if (tick) next = START;
            end
            START: begin
                tx_next = 1'b0;
                tx_done_next = 1'b1;
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        bit_count_next = 0;
                        next = DATA;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            DATA: begin
                tx_next = temp_data_reg[bit_count_reg];
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        tick_count_next = 0;
                        if (bit_count_reg == 7) begin
                            next = STOP;
                        end else begin
                            bit_count_next = bit_count_reg + 1;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (tick) begin
                    if (tick_count_reg == 15) begin
                        next = IDLE;
                        tick_count_next = 0;
                    end else begin
                        tick_count_next = tick_count_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////

module baud_tick_gen (
    input  logic clk,
    input  logic rst,
    output logic baud_tick
);
    parameter int BAUD_RATE = 9600;
    localparam int BAUD_COUNT = 100_000_000 / (BAUD_RATE * 16);

    logic [$clog2(BAUD_COUNT)-1:0] count_reg, count_next;
    logic tick_reg, tick_next;

    assign baud_tick = tick_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_reg  <= 0;
            count_reg <= 0;
        end else begin
            tick_reg  <= tick_next;
            count_reg <= count_next;
        end
    end

    always_comb begin
        tick_next  = 1'b0;
        count_next = count_reg;
        if (count_reg == BAUD_COUNT - 1) begin
            tick_next  = 1'b1;
            count_next = 0;
        end else begin
            tick_next  = 1'b0;
            count_next = count_reg + 1;
        end
    end
endmodule
