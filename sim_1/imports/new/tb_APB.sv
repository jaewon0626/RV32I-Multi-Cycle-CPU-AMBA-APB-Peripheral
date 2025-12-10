`timescale 1ns / 1ps

interface uart_interface;
    logic         clk;
    logic         rst;
    logic         rx;
    logic         tx;
    logic [ 7:0]  rx_data;
    logic         cmd_start;
    logic [ 7:0]  internal_rx_data;
    logic [ 7:0]  o_rx_data;

    // APB Interface Signals
    logic [ 3:0]  PADDR;
    logic [31:0]  PWDATA;
    logic         PWRITE;
    logic         PENABLE;
    logic         PSEL;
    logic [31:0]  PRDATA;
    logic         PREADY;
endinterface

class transaction;
    rand bit [7:0] uart_send_data; // Generator가 생성한 원본 데이터
    bit [7:0]      uart_re_data;   // Monitor가 tx 핀에서 수신한 데이터
    bit            rx;
    bit            tx;

endclass


class generator;
    transaction          trans;
    mailbox #(transaction) gen2drv_mbox;
    event                gen_next_event;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            trans = new();
            assert (trans.randomize())
            else $error("[GEN] tr.randomize() error");
            gen2drv_mbox.put(trans);
            $display("[GENERATOR]");
            $display("Rx Expect Data = %h", trans.uart_send_data);
            @gen_next_event;
        end
    endtask

endclass


// =================================================================
// Driver (APB Agent 역할 통합)
// =================================================================
class driver;
    transaction          trans;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) drv2mon_mbox; // [수정] ApbAgent 대신 Monitor로 직접 전달
    virtual uart_interface uart_if;

    parameter CLOCK_PERIOD_NS = 10;
    parameter BITPERCLOCK     = 10416; // 100_000_000/9600
    parameter BIT_PERIOD      = BITPERCLOCK * CLOCK_PERIOD_NS;

    // --- [추가] ApbAgent로부터 가져온 주소 정의 ---
    localparam logic [3:0] USR_ADDR = 4'h0; // 0x0
    localparam logic [3:0] ULS_ADDR = 4'h4; // 0x4
    localparam logic [3:0] UWD_ADDR = 4'h8; // 0x8
    localparam logic [3:0] URD_ADDR = 4'hC; // 0xC

    // --- [추가] ApbAgent로부터 가져온 USR 비트 정의 ---
    localparam int TX_NOT_FULL_BIT  = 1; // USR[1]이 !full_TX
    localparam int RX_NOT_EMPTY_BIT = 0; // USR[0]이 !empty_RX
    // ---------------------------------------------

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_interface uart_if,
                 mailbox#(transaction) drv2mon_mbox); // [수정]
        this.gen2drv_mbox = gen2drv_mbox;
        this.uart_if      = uart_if;
        this.drv2mon_mbox = drv2mon_mbox; // [수정]
    endfunction

    task reset();
        uart_if.clk = 0;
        uart_if.rst = 1;
        uart_if.rx  = 1;
        uart_if.tx  = 1;
        repeat (2) @(posedge uart_if.clk);
        uart_if.rst = 0;
        @(posedge uart_if.clk);
        $display("[DRIVER] reset");
    endtask

    // --- UART RX핀으로 데이터 전송 ---
    task send_data(bit [7:0] uart_send_data);
        uart_if.rx = 0; // Start bit
        #(BIT_PERIOD);
        for (int i = 0; i < 8; i = i + 1) begin
            uart_if.rx = uart_send_data[i];
            #(BIT_PERIOD);
        end
        uart_if.rx = 1; // Stop bit
        #(BIT_PERIOD);
    endtask

    // --- [추가] ApbAgent로부터 가져온 APB Read Task ---
    task apb_read(input logic [3:0] addr, output logic [31:0] data);
        logic [31:0] read_value;
        @(posedge uart_if.clk);
        // APB Setup
        uart_if.PADDR   = addr;
        uart_if.PWRITE  = 0;
        uart_if.PSEL    = 1;
        uart_if.PENABLE = 0;

        @(posedge uart_if.clk);
        // APB Access
        uart_if.PENABLE = 1;

        wait (uart_if.PREADY == 1);

        read_value = uart_if.PRDATA;

        @(posedge uart_if.clk);
        // APB End
        uart_if.PSEL    = 0;
        uart_if.PENABLE = 0;
        data            = read_value;
    endtask

    // --- [추가] ApbAgent로부터 가져온 APB Write Task ---
    task apb_write(input logic [3:0] addr, input logic [31:0] data);
        @(posedge uart_if.clk);
        // APB Setup
        uart_if.PADDR   = addr;
        uart_if.PWDATA  = data;
        uart_if.PWRITE  = 1;
        uart_if.PSEL    = 1;
        uart_if.PENABLE = 0;

        @(posedge uart_if.clk);
        // APB Access
        uart_if.PENABLE = 1;

        wait (uart_if.PREADY == 1);

        @(posedge uart_if.clk);
        // APB End
        uart_if.PSEL    = 0;
        uart_if.PENABLE = 0;
    endtask


    // --- [수정] Driver Run Task (APB 로직 포함) ---
    task run();
        logic [31:0] read_data; // APB 읽기용 변수

        forever begin
            #1;
            // 1. Generator로부터 트랜잭션 수신
            gen2drv_mbox.get(trans);
            @(posedge uart_if.clk);

            // 2. DUT의 RX 핀으로 UART 데이터 전송
            send_data(trans.uart_send_data);
            $display("[DRIVER] Sent %h to RX pin", trans.uart_send_data);

            // 3. [APB 로직] RX FIFO에 데이터가 수신될 때까지 폴링
            $display(
                "[DRIVER-APB] Waiting for RX data... (Checking USR[0] == 1)");
            begin
                logic [31:0] current_status;
                do begin
                    apb_read(USR_ADDR, current_status);
                    $display(
                        "[DRIVER-APB] Polling RX... Read USR: 0x%h. (Bit[0] is: %b)",
                        current_status, current_status[RX_NOT_EMPTY_BIT]);
                    @(posedge uart_if.clk);
                end while (current_status[RX_NOT_EMPTY_BIT] == 0); // !empty_RX
            end

            // 4. [APB 로직] RX FIFO에서 데이터 읽기 (PADDR = 0xC)
            apb_read(URD_ADDR, read_data);
            $display("[DRIVER-APB] Read %h from RX FIFO", read_data[7:0]);

            // 5. (선택적) 읽은 데이터가 Driver가 보낸 데이터와 일치하는지 확인
            if (read_data[7:0] == trans.uart_send_data) begin
                $display("[DRIVER-APB] PASS! RX Path data matched (%h)",
                         trans.uart_send_data);
            end else begin
                $display(
                    "[DRIVER-APB] FAIL! RX Path data MISMATCH. (Sent: %h, Read: %h)",
                    trans.uart_send_data, read_data[7:0]);
            end

            // 6. [APB 로직] TX FIFO에 공간이 생길 때까지 폴링
            $display(
                "[DRIVER-APB] Waiting for TX FIFO space... (Checking USR[1] == 1)");
            begin
                logic [31:0] current_status;
                do begin
                    apb_read(USR_ADDR, current_status);
                    $display(
                        "[DRIVER-APB] Polling TX... Read USR: 0x%h. (Bit[1] is: %b)",
                        current_status, current_status[TX_NOT_FULL_BIT]);
                    @(posedge uart_if.clk);
                end while (current_status[TX_NOT_FULL_BIT] == 0); // !full_TX
            end

            // 7. [APB 로직] TX FIFO에 데이터 쓰기 (루프백) (PADDR = 0x8)
            apb_write(UWD_ADDR, read_data);
            $display("[DRIVER-APB] Wrote %h to TX FIFO (Loopback)",
                     read_data[7:0]);

            // 8. Monitor에게 트랜잭션 전달 (TX 핀 모니터링 시작)
            drv2mon_mbox.put(trans);
        end
    endtask
endclass


// =================================================================
// ApbAgent
// =================================================================
// [삭제] ApbAgent 클래스 전체가 제거됨


// =================================================================
// Monitor
// =================================================================
class monitor;
    transaction          trans;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) drv2mon_mbox; // [수정] apb2mon_mbox -> drv2mon_mbox
    virtual uart_interface uart_if;

    parameter CLOCK_PERIOD_NS = 10;
    parameter BITPERCLOCK     = 10416;
    parameter BIT_PERIOD      = BITPERCLOCK * CLOCK_PERIOD_NS;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_interface uart_if,
                 mailbox#(transaction) drv2mon_mbox); // [수정]
        this.mon2scb_mbox = mon2scb_mbox;
        this.uart_if      = uart_if;
        this.drv2mon_mbox = drv2mon_mbox; // [수정]
    endfunction

    task run();
        localparam bit VERBOSE_DEBUG = 1;
        forever begin
            // [수정] Driver가 TX FIFO에 쓰기를 완료할 때까지 대기
            drv2mon_mbox.get(trans);

            // DUT가 tx 핀으로 데이터를 전송할 때까지 대기
            wait (uart_if.tx == 0); // 1. Start bit 감지
            #(BIT_PERIOD + BIT_PERIOD / 2); // 2. D0 비트의 *중간* 지점으로 이동

            trans.uart_re_data[0] = uart_if.tx; // 3. D0 비트 *중간*에서 샘플링

            for (int i = 1; i < 8; i = i + 1) begin // 4. D1 ~ D7
                #(BIT_PERIOD); // 5. 다음 비트의 *중간* 지점으로 이동
                trans.uart_re_data[i] = uart_if.tx; // 6. 해당 비트 *중간*에서 샘플링
            end
            #(BIT_PERIOD / 2); // 7. Stop bit의 중간을 지날 때까지 대기

            if (VERBOSE_DEBUG) begin
                $display("[MONITOR]");
                $display(
                    "+--------------------------------------------------+");
                $display(
                    "| Value    | %1b  %1b  %1b  %1b  %1b  %1b  %1b  %1b |",
                    trans.uart_re_data[7], trans.uart_re_data[6],
                    trans.uart_re_data[5], trans.uart_re_data[4],
                    trans.uart_re_data[3], trans.uart_re_data[2],
                    trans.uart_re_data[1], trans.uart_re_data[0]);
                $display("| Received Tx Data : 0x%h                       |",
                         trans.uart_re_data);
                $display(
                    "+--------------------------------------------------+");
            end

            @(posedge uart_if.clk);
            mon2scb_mbox.put(trans);
        end
    endtask

endclass


class scoreboard;
    transaction          trans;
    mailbox #(transaction) mon2scb_mbox;
    event                gen_next_event;

    int success_count;
    int fail_count;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(trans);
            if (trans.uart_send_data == trans.uart_re_data) begin
                $display("[SCOREBOARD]");
                $display("| UART verification success");
                $display("| - SEND DATA     : 0x%h", trans.uart_send_data);
                $display("| - RECEIVED DATA : 0x%h", trans.uart_re_data);
                success_count = success_count + 1;
            end else begin
                $display("[SCOREBOARD]");
                $display("| UART verification failed");
                $display("| - SEND DATA     : 0x%h", trans.uart_send_data);
                $display("| - RECEIVED DATA : 0x%h", trans.uart_re_data);
                fail_count = fail_count + 1;
            end
            ->gen_next_event;
        end
    endtask

    task report();
        int  total_count = success_count + fail_count;

        $display("================================================");
        $display("                   TEST RESULT                  ");
        $display("   Total Test : %0d", total_count);
        $display("   Test Passed    : %0d", success_count);
        $display("   Test Failed    : %0d", fail_count);

        if (fail_count == 0 && total_count > 0) begin
            $display("   STATUS         : All Passed            ");
        end else if (total_count == 0) begin
            $display("   STATUS         : Test Not Run          ");
        end else begin
            $display("   STATUS         : Test Failed       ");
        end
        $display("================================================");
    endtask

endclass


// =================================================================
// Environment
// =================================================================
class environment;
    transaction          trans;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) drv2mon_mbox; // [수정] Driver -> Monitor
    // [삭제] drv2apb_mbox, apb2mon_mbox

    event gen_next_event;

    generator  gen;
    driver     drv;
    // [삭제] ApbAgent apb_agent;
    monitor    mon;
    scoreboard scb;

    virtual uart_interface uart_if; // 인터페이스 핸들

    function new(virtual uart_interface uart_if);
        this.uart_if = uart_if; // 인터페이스 핸들 저장

        gen2drv_mbox = new();
        mon2scb_mbox = new();
        drv2mon_mbox = new(); // [수정]
        // [삭제] drv2apb_mbox, apb2mon_mbox

        gen = new(gen2drv_mbox, gen_next_event);
        
        // [수정] drv 생성자 변경
        drv = new(gen2drv_mbox, uart_if, drv2mon_mbox); 

        // [삭제] apb_agent 생성자
        
        // [수정] mon 생성자 변경
        mon = new(mon2scb_mbox, uart_if, drv2mon_mbox); 

        scb = new(mon2scb_mbox, gen_next_event);
    endfunction


    task reset();
        drv.reset();

        // APB 신호 초기화
        uart_if.PADDR   <= 4'bx;
        uart_if.PWDATA  <= 32'bx;
        uart_if.PWRITE  <= 1'b0;
        uart_if.PENABLE <= 1'b0;
        uart_if.PSEL    <= 1'b0;

        @(posedge uart_if.clk);
    endtask

    task run();
        fork
            gen.run(100);
            drv.run();
            // [삭제] apb_agent.run();
            mon.run();
            scb.run();
        join_any
        
        #10us; // 마지막 트랜잭션이 완료될 시간
        scb.report();
        $display("finished");
        $stop;
    endtask
endclass


// =================================================================
// TB Top
// =================================================================
module tb_UART ();

    uart_interface uart_interface_tb ();
    environment    env;

    // DUT: uart_Periph
    UART_Periph dut (
        .PCLK(uart_interface_tb.clk),
        .PRESET(uart_interface_tb.rst),
        .PADDR(uart_interface_tb.PADDR),
        .PWDATA(uart_interface_tb.PWDATA),
        .PWRITE(uart_interface_tb.PWRITE),
        .PENABLE(uart_interface_tb.PENABLE),
        .PSEL(uart_interface_tb.PSEL),
        .PRDATA(uart_interface_tb.PRDATA),
        .PREADY(uart_interface_tb.PREADY),
        .rx(uart_interface_tb.rx),
        .tx(uart_interface_tb.tx)
    );

    // DUT 내부 신호 모니터링
    assign uart_interface_tb.internal_rx_data = dut.U_RX.rx_data;


    always #5 uart_interface_tb.clk = ~uart_interface_tb.clk;

    initial begin
        uart_interface_tb.clk = 0;
        env = new(uart_interface_tb);
        env.reset();
        env.run();
    end
endmodule