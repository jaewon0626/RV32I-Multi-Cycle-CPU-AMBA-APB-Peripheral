`timescale 1ns / 1ps
module FND_Periph (
    // global signal
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    input  logic [ 4:0] PADDR,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    // external signal
    output logic [ 3:0] fnd_com,
    output logic [ 7:0] fnd_data
);

    logic        FCR;  // FND_Control_Register
    // FND 주변 장치의 전반적인 동작 상태를 제어하는 레지스터
    // CPU가 slv_reg0에 1을 쓰면 FND 동작, 0을 쓰면 FND 동작 정지

    logic [13:0] FDR;  // FND_Data_Register
    // FND에 표시할 실제 숫자 데이터를 저장하는 레지스터
    // CPU가 slv_reg1에 쓰는 값을 FDR에 저장하여 FND에 출력됨

    logic [ 1:0] seg_sel;
    logic        o_clk;

    APB_Intf_FND u_APB_Intf_FND (.*);
    FND_controller u_FND_controller (.*);

    // 1kHz 클럭 분주기
    clk_divider u_clk_divider (
        .clk  (PCLK),
        .reset(PRESET),
        .o_clk(o_clk)
    );

    // 7-segment 선택 카운터 (0~3)
    counter #(2) u_counter (  // Modified to count up to 3
        .clk(o_clk),
        .reset(PRESET),
        .seg_sel(seg_sel)
    );

endmodule

///////////////////////////////////////////////////////////////////////////////////////

module APB_Intf_FND (
    // global signal
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    input  logic [ 4:0] PADDR,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    //output signals
    output logic        FCR,
    output logic [13:0] FDR
);

    logic [31:0] slv_reg0, slv_reg1, slv_reg2, slv_reg3, slv_reg5;
    logic [13:0] slv_reg4;

    assign FCR = slv_reg0[0];
    assign FDR = slv_reg1[13:0];

    assign PREADY = PSEL & PENABLE; 

    // --- BCD 변환 로직 (파이프라이닝 복원) ---
    logic [7:0] bcd_0, bcd_1, bcd_2, bcd_3;                 // 1단계 조합 논리 결과
    logic [7:0] bcd_0_reg, bcd_1_reg, bcd_2_reg, bcd_3_reg; // 2단계 파이프라인 레지스터

    // 1단계: 나눗셈/모듈로 연산 (가장 느린 조합 경로)
    always_comb begin
        bcd_3 = (slv_reg4 / 1000) + 8'd48;
        bcd_2 = ((slv_reg4 % 1000) / 100) + 8'd48;
        bcd_1 = ((slv_reg4 % 100) / 10) + 8'd48;
        bcd_0 = (slv_reg4 % 10) + 8'd48;
    end

    always_ff @( posedge PCLK or posedge PRESET ) begin
        if(PRESET)begin
            bcd_3_reg <= 0;
            bcd_2_reg <= 0;
            bcd_1_reg <= 0;
            bcd_0_reg <= 0;
        end
        else begin
            bcd_3_reg <= bcd_3;
            bcd_2_reg <= bcd_2;
            bcd_1_reg <= bcd_1;
            bcd_0_reg <= bcd_0;
        end
    end

    always_ff @(posedge PCLK or posedge PRESET) begin
        if (PRESET) begin
            slv_reg5 <= 0;
        end else begin
            slv_reg5 <= {bcd_3_reg, bcd_2_reg, bcd_1_reg, bcd_0_reg};
        end
    end


    // --- 레지스터 쓰기 로직 ---
    always_ff @(posedge PCLK or posedge PRESET) begin
        if (PRESET) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            slv_reg3 <= 0;
            slv_reg4 <= 0;

        end else begin
            if (PSEL && PENABLE) begin
                if (PWRITE) begin
                    case (PADDR[4:2])
                        3'd0: slv_reg0 <= PWDATA;
                        3'd1: slv_reg1 <= PWDATA;
                        3'd3: slv_reg3 <= PWDATA;
                        3'd4: slv_reg4 <= PWDATA;
                    endcase
                end
            end
        end
    end

    // PRDATA 로직 간소화
    always_comb begin
        PRDATA = 32'b0;
        if (PSEL && PENABLE && !PWRITE) begin
            case (PADDR[4:2])
                3'd0: PRDATA = slv_reg0;
                3'd1: PRDATA = slv_reg1;
                3'd3: PRDATA = slv_reg3;
                3'd5: PRDATA = slv_reg5; // BCD/ASCII Read-Only
                default: ;
            endcase
        end 
    end

endmodule

///////////////////////////////////////////////////////////////////////////////////////

module FND_controller (
    input  logic        FCR,
    // input logic [3:0] FMR,
    input  logic [13:0] FDR,
    output logic [ 3:0] fnd_com,
    output logic [ 7:0] fnd_data,
    input  logic [ 1:0] seg_sel

);

    logic [3:0] fnd_final_data, fnd_0, fnd_1, fnd_2, fnd_3;

    assign fnd_3 = FDR / 1000;
    assign fnd_2 = (FDR % 1000) / 100;
    assign fnd_1 = (FDR % 100) / 10;
    assign fnd_0 = FDR % 10;

    // fnd_com 자리 선택
    always_comb begin
        case (seg_sel)
            2'b00:   fnd_com = FCR ? 4'b1110 : 4'b1111;  // Digit 0 활성화
            2'b01:   fnd_com = FCR ? 4'b1101 : 4'b1111;  // Digit 1 활성화
            2'b10:   fnd_com = FCR ? 4'b1011 : 4'b1111;  // Digit 2 활성화
            2'b11:   fnd_com = FCR ? 4'b0111 : 4'b1111;  // Digit 3 활성화
            default: fnd_com = 4'b1111;  // 모든 자리 비활성화
        endcase
    end

    // 표시할 최종 데이터 선택
    always_comb begin
        case (seg_sel)
            2'b00:   fnd_final_data = fnd_0;
            2'b01:   fnd_final_data = fnd_1;
            2'b10:   fnd_final_data = fnd_2;
            2'b11:   fnd_final_data = fnd_3;
            default: fnd_final_data = 4'b0000;
        endcase
    end

    seg_decoder u_seg_decoder (
        .data(fnd_final_data),
        .seg_value(fnd_data),
        .seg_sel(seg_sel)
    );

endmodule

///////////////////////////////////////////////////////////////////////////////////////

module seg_decoder (
    input  logic [3:0] data,
    output logic [7:0] seg_value,
    input  logic [1:0] seg_sel
);
    logic [7:0] bcdtoseg;

    always_comb begin
        case (data)
            4'd0: bcdtoseg = 8'b11000000;  // 0
            4'd1: bcdtoseg = 8'b11111001;  // 1
            4'd2: bcdtoseg = 8'b10100100;  // 2
            4'd3: bcdtoseg = 8'b10110000;  // 3
            4'd4: bcdtoseg = 8'b10011001;  // 4
            4'd5: bcdtoseg = 8'b10010010;  // 5
            4'd6: bcdtoseg = 8'b10000010;  // 6
            4'd7: bcdtoseg = 8'b11111000;  // 7
            4'd8: bcdtoseg = 8'b10000000;  // 8
            4'd9: bcdtoseg = 8'b10010000;  // 9
            4'd10: bcdtoseg = 8'b10001000;  // A
            4'd11: bcdtoseg = 8'b10000011;  // b
            4'd12: bcdtoseg = 8'b11000110;  // C
            4'd13: bcdtoseg = 8'b10100001;  // d
            4'd14: bcdtoseg = 8'b10000110;  // E
            4'd15: bcdtoseg = 8'b10001110;  // F
            default: bcdtoseg = 8'b11111111;  // blank or error
        endcase
    end

    assign seg_value = bcdtoseg;

endmodule

///////////////////////////////////////////////////////////////////////////////////////

// 1kHz 클럭 분주기 (unchanged)
module clk_divider (
    input  logic clk,
    input  logic reset,
    output logic o_clk
);
    parameter CLK_DIV = 50000; // 50MHz -> 1KHz
    reg [15:0] r_count;
    reg r_clk;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_count <= 0;
            r_clk   <= 1'b0;
        end else begin
            if (r_count == CLK_DIV - 1) begin
                r_count <= 0;
                r_clk   <= ~r_clk;
            end else begin
                r_count <= r_count + 1;
            end
        end
    end

    assign o_clk = r_clk;
endmodule

///////////////////////////////////////////////////////////////////////////////////////

// 7-Segment 선택을 위한 카운터 (modified for 4 segments)
module counter #(
    parameter WIDTH = 2  // Width for 4 segments (0 to 3)
) (
    input logic clk,
    input logic reset,
    output logic [WIDTH-1:0] seg_sel
);
    always @(posedge clk or posedge reset) begin
        if (reset) seg_sel <= 0;
        else seg_sel <= seg_sel + 1;
    end
endmodule

// `timescale 1ns / 1ps
// module FND_Periph (
//     // global signal
//     input  logic        PCLK,
//     input  logic        PRESET,
//     // APB Interface Signals
//     input  logic [ 4:0] PADDR,
//     input  logic        PSEL,
//     input  logic        PENABLE,
//     input  logic        PWRITE,
//     input  logic [31:0] PWDATA,
//     output logic [31:0] PRDATA,
//     output logic        PREADY,
//     // external signal
//     output logic [ 3:0] fnd_com,
//     output logic [ 7:0] fnd_data
// );

//     logic        FCR;  // FND_Control_Register
//     // FND 주변 장치의 전반적인 동작 상태를 제어하는 레지스터
//     // CPU가 slv_reg0에 1을 쓰면 FND 동작, 0을 쓰면 FND 동작 정지

//     logic [13:0] FDR;  // FND_Data_Register
//     // FND에 표시할 실제 숫자 데이터를 저장하는 레지스터
//     // CPU가 slv_reg1에 쓰는 값을 FDR에 저장하여 FND에 출력됨

//     logic [ 1:0] seg_sel;
//     logic        o_clk;

//     APB_Intf_FND u_APB_Intf_FND (.*);
//     FND_controller u_FND_controller (.*);

//     // 1kHz 클럭 분주기
//     clk_divider u_clk_divider (
//         .clk  (PCLK),
//         .reset(PRESET),
//         .o_clk(o_clk)
//     );

//     // 7-segment 선택 카운터 (0~3)
//     counter #(2) u_counter (  // Modified to count up to 3
//         .clk(o_clk),
//         .reset(PRESET),
//         .seg_sel(seg_sel)
//     );

// endmodule

// ///////////////////////////////////////////////////////////////////////////////////////

// module APB_Intf_FND (
//     // global signal
//     input  logic        PCLK,
//     input  logic        PRESET,
//     // APB Interface Signals
//     input  logic [ 4:0] PADDR,
//     input  logic        PSEL,
//     input  logic        PENABLE,
//     input  logic        PWRITE,
//     input  logic [31:0] PWDATA,
//     output logic [31:0] PRDATA,
//     output logic        PREADY,
//     //output signals
//     output logic        FCR,
//     output logic [13:0] FDR
// );

//     logic [31:0] slv_reg0, slv_reg1, slv_reg2, slv_reg3, slv_reg4, slv_reg5;

//     assign FCR = slv_reg0[0];
//     assign FDR = slv_reg1[13:0];

//     logic [7:0] bcd_0, bcd_1, bcd_2, bcd_3;

//     // slv_reg4 값을 BCD-ASCII로 변환
//     always_comb begin
//         bcd_3 = (slv_reg4 / 1000) + 8'd48;
//         bcd_2 = ((slv_reg4 % 1000) / 100) + 8'd48;
//         bcd_1 = ((slv_reg4 % 100) / 10) + 8'd48;
//         bcd_0 = (slv_reg4 % 10) + 8'd48;
//     end

//     // slv_reg5 Read-Only BCD/ASCII 업데이트
//     always_ff @(posedge PCLK or posedge PRESET) begin
//         if (PRESET) begin
//             slv_reg5 <= 0;
//         end else begin
//             slv_reg5 <= {bcd_3, bcd_2, bcd_1, bcd_0};
//         end
//     end

//     always_ff @(posedge PCLK or posedge PRESET) begin
//         if (PRESET) begin
//             slv_reg0 <= 0;
//             slv_reg1 <= 0;
//             // slv_reg2 <= 0;
//             slv_reg3 <= 0;
//             slv_reg4 <= 0;

//         end else begin
//             PREADY <= 0;
//             if (PSEL && PENABLE) begin
//                 PREADY <= 1;
//                 if (PWRITE) begin
//                     case (PADDR[4:2])
//                         3'd0: slv_reg0 <= PWDATA;
//                         3'd1: slv_reg1 <= PWDATA;
//                         3'd3: slv_reg3 <= PWDATA;
//                         3'd4: slv_reg4 <= PWDATA;
//                     endcase
//                 end
//             end
//         end
//     end

//     // 기존 assign 제거하고 아래 추가
//     always_comb begin
//         if (PSEL && PENABLE && !PWRITE) begin
//             case (PADDR[4:2])
//                 3'd0: PRDATA = slv_reg0;
//                 3'd1: PRDATA = slv_reg1;
//                 // 3'd2: PRDATA = slv_reg2;
//                 3'd3: PRDATA = slv_reg3;
//                 3'd5: PRDATA = slv_reg5; // BCD/ASCII Read-Only
//                 default: PRDATA = 32'b0;
//             endcase
//         end else begin
//             PRDATA = 32'b0;
//         end
//     end

// endmodule

// ///////////////////////////////////////////////////////////////////////////////////////

// module FND_controller (
//     input  logic        FCR,
//     // input logic [3:0] FMR,
//     input  logic [13:0] FDR,
//     output logic [ 3:0] fnd_com,
//     output logic [ 7:0] fnd_data,
//     input  logic [ 1:0] seg_sel
// );

//     logic [3:0] fnd_final_data, fnd_0, fnd_1, fnd_2, fnd_3;

//     assign fnd_3 = FDR / 1000;
//     assign fnd_2 = (FDR % 1000) / 100;
//     assign fnd_1 = (FDR % 100) / 10;
//     assign fnd_0 = FDR % 10;

//     // fnd_com 자리 선택
//     always_comb begin
//         case (seg_sel)
//             2'b00:   fnd_com = FCR ? 4'b1110 : 4'b1111;  // Digit 0 활성화
//             2'b01:   fnd_com = FCR ? 4'b1101 : 4'b1111;  // Digit 1 활성화
//             2'b10:   fnd_com = FCR ? 4'b1011 : 4'b1111;  // Digit 2 활성화
//             2'b11:   fnd_com = FCR ? 4'b0111 : 4'b1111;  // Digit 3 활성화
//             default: fnd_com = 4'b1111;  // 모든 자리 비활성화
//         endcase
//     end

//     // 표시할 최종 데이터 선택
//     always_comb begin
//         case (seg_sel)
//             2'b00:   fnd_final_data = fnd_0;
//             2'b01:   fnd_final_data = fnd_1;
//             2'b10:   fnd_final_data = fnd_2;
//             2'b11:   fnd_final_data = fnd_3;
//             default: fnd_final_data = 4'b0000;
//         endcase
//     end

//     seg_decoder u_seg_decoder (
//         .data(fnd_final_data),
//         .seg_value(fnd_data),
//         .seg_sel(seg_sel)
//     );

// endmodule

// ///////////////////////////////////////////////////////////////////////////////////////

// module seg_decoder (
//     input  logic [3:0] data,
//     output logic [7:0] seg_value,
//     input  logic [1:0] seg_sel
// );
//     logic [7:0] bcdtoseg;

//     always_comb begin
//         case (data)
//             4'd0: bcdtoseg = 8'b11000000;  // 0
//             4'd1: bcdtoseg = 8'b11111001;  // 1
//             4'd2: bcdtoseg = 8'b10100100;  // 2
//             4'd3: bcdtoseg = 8'b10110000;  // 3
//             4'd4: bcdtoseg = 8'b10011001;  // 4
//             4'd5: bcdtoseg = 8'b10010010;  // 5
//             4'd6: bcdtoseg = 8'b10000010;  // 6
//             4'd7: bcdtoseg = 8'b11111000;  // 7
//             4'd8: bcdtoseg = 8'b10000000;  // 8
//             4'd9: bcdtoseg = 8'b10010000;  // 9
//             4'd10: bcdtoseg = 8'b10001000;  // A
//             4'd11: bcdtoseg = 8'b10000011;  // b
//             4'd12: bcdtoseg = 8'b11000110;  // C
//             4'd13: bcdtoseg = 8'b10100001;  // d
//             4'd14: bcdtoseg = 8'b10000110;  // E
//             4'd15: bcdtoseg = 8'b10001110;  // F
//             default: bcdtoseg = 8'b11111111;  // blank or error
//         endcase
//     end

//     assign seg_value = bcdtoseg;

// endmodule

// ///////////////////////////////////////////////////////////////////////////////////////

// // 1kHz 클럭 분주기 (unchanged)
// module clk_divider (
//     input  logic clk,
//     input  logic reset,
//     output logic o_clk
// );
//     parameter CLK_DIV = 50000; // 50MHz -> 1KHz
//     reg [15:0] r_count;
//     reg r_clk;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             r_count <= 0;
//             r_clk   <= 1'b0;
//         end else begin
//             if (r_count == CLK_DIV - 1) begin
//                 r_count <= 0;
//                 r_clk   <= ~r_clk;
//             end else begin
//                 r_count <= r_count + 1;
//             end
//         end
//     end

//     assign o_clk = r_clk;
// endmodule

// ///////////////////////////////////////////////////////////////////////////////////////

// // 7-Segment 선택을 위한 카운터 (modified for 4 segments)
// module counter #(
//     parameter WIDTH = 2  // Width for 4 segments (0 to 3)
// ) (
//     input logic clk,
//     input logic reset,
//     output logic [WIDTH-1:0] seg_sel
// );
//     always @(posedge clk or posedge reset) begin
//         if (reset) seg_sel <= 0;
//         else seg_sel <= seg_sel + 1;
//     end
// endmodule
