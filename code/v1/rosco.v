// rosco logic in verilog
// Malcolm Harrow, January 2025
// MIT License

// Memory map:
// * Onboard RAM    : $00000000 - $000FFFFF (1MB)
// * Expansion space: $00100000 - $00DFFFFF (13MB)
// * ROM            : $00E00000 - $00EFFFFF (1MB)
// * IO             : $00F00000 - $FFFFFFFF (1MB)

// TO DO 
// Check how reset works ..
// Check all PIN assignments in fit file are ok


`default_nettype none

module rosco (
	input  CLK, 
	input  RESETn,
	input  [23:18] A_HIGH,
	input  [16:6] A_MED,
	input  [3:0] A_LOW,
    input  DUAIRQ, IRQ2, IRQ3, IRQ5, IRQ6,
	input  SIZ0, SIZ1,
	input  RW,
	input  [2:0] FC,
    input  DSn,
    input  ASn,
	input  HWRST,

	inout  DTACKn,
	inout  HALT,

	output BERRn,
	output WR,
	output LDSn, UDSn,
	output EXPSELn, EVENRAMSELn, ODDRAMSELn, EVENROMSELn, ODDROMSELn, 
	output IOSELn, 
	output DUASELn,
	output reg ESIG, /* This is the E signal, yosys doesnt like me calling it just 'E' */
	output reg IPL0n, 
	output reg IPL1n, 
	output reg IPL2n, 
	output DUAIACKn,
	output RUNLED,

	output PPDTACK   // has to be an output for the tri-state logic to work
);

	// Reconstruct the full address bus
	wire [23:0] A = {A_HIGH, 1'b0, A_MED, 2'b0, A_LOW};
	// Reconstruct UDS and LDS
	wire wireUDSn = !(!DSn && !A[0]);
	wire wireLDSn = !((!DSn && !A[0]) || (!DSn && !SIZ0) || (!DSn && SIZ1));
	// Set CPU space - FC all high when responding to interupt.  Note +ve logic
	wire wireCPUSP = !HWRST && (FC[2:0] == 3'b111);

	// GLUE 
	// Tri state is not well supported by yosys .. do not use these in any equations ...
	assign HALT = HWRST ? 1'b0 : 1'bZ;
	assign RESETn = HWRST ? 1'b0 : 1'bZ;
	assign RUNLED = HWRST; 
	
	assign DUAIACKn = !(!wireCPUSP && !ASn && (A[19] == 1) && (A[3:1] == 3'b100)); 

	// // Count AS (memory access) cycles to set BOOT for the first 4 memory reads
	reg [2:0] bootcounter = 0;
	reg boot;

	initial begin
		boot <= 1'b0;
		bootcounter <= 0;
	end
	
	always @(posedge ASn) begin
		if (HWRST) begin // should really check halt and reset, but tri state not well handled
			bootcounter <= 0;
			boot <= 1'b0;
		end
		else begin
			if (!boot) begin
				bootcounter <= bootcounter + 3'b1;
				if (bootcounter == 4) 
					boot <= 1'b1;
			end
		end
	end


	// ADDRESS DECODER
	// ROM at 0xE00000 - (0x000000 on BOOT)
	wire rom = !boot || A[23:20] == 4'hE;
	assign ODDROMSELn = !(!wireCPUSP && !ASn && !wireLDSn && rom);
	assign EVENROMSELn = !(!wireCPUSP && !ASn && !wireUDSn && rom);

	// // RAM at 0x000000 (1 MB)
	wire ram = boot && (A[23:20] == 4'h0);
	assign ODDRAMSELn = !(!wireCPUSP && !ASn && !wireLDSn && ram);
	assign EVENRAMSELn = !(!wireCPUSP && !ASn && !wireUDSn && ram);
	
	// // IO at 0xF00000 
	wire io = A[23:20] == 4'hF;
	wire wireIOSELn = !(!wireCPUSP && io); // Used below
	assign IOSELn = wireIOSELn;

	// // Expansion at 0x100000 - 0xD00000
	wire exp = (A[23:20] >= 4'h1) && (A[23:20] <= 4'hD);
	assign EXPSELn = !(!wireCPUSP && !ASn && exp);
	
	assign WR = !RW;

	assign PPDTACK = !EVENROMSELn || !ODDROMSELn || !EVENRAMSELn || !ODDRAMSELn || !EXPSELn;
	assign DTACKn = PPDTACK ? 1'b0 : 1'bZ;


	// DUART SELECT
	assign DUASELn = !(A[19:6] == 0 && !wireLDSn && !wireIOSELn);


	// // CPU GLUE
	assign UDSn = wireUDSn;
	assign LDSn = wireLDSn;

	// according the datasheet, a single period of clock E 
	// consists of 10 MC68000 clock periods (six clocks low, 4 clocks high)
	// E is renamed ESIG due to yosys giving wierd errors if I call the port just E

	reg [3:0] ecounter;
	initial begin
		ESIG <= 1'b0;
		ecounter <= 0;
	end

	always @(posedge CLK) begin
		if (ecounter == 6) begin
			ESIG <= 1'b1;
			ecounter <= ecounter + 1;
		end else if (ecounter == 10)begin
			ecounter <= 0;
			ESIG <= 1'b0;
		end else begin 
			ecounter <= ecounter + 1;
		end 
	end


	// WATCHDOG
	// I think the original code is counting to 128 .. about 10ms on a 12MHz 68010
	
	reg [6:0] wdcounter;
	wire wden = !ASn || (wireCPUSP && A[19]);

	always @(posedge CLK) begin
		if (!wden) begin
			wdcounter <= 7'b0;
		end else if (wdcounter != 7'b1111111) begin
			wdcounter <= wdcounter + 1;
		end 
	end

	assign BERRn = (wdcounter != 7'b1111111);


	// IRQ PRIORITY ENCODER
	always @(*) begin
		if (IRQ6) begin
			IPL0n <= 1;
			IPL1n <= 0;
			IPL2n <= 0;
		end
		else
		if (IRQ5) begin
			IPL0n <= 0;
			IPL1n <= 1;
			IPL2n <= 0;
		end
		else if (IRQ3) begin
			IPL0n <= 0;
			IPL1n <= 0;
			IPL2n <= 1;
		end
		else if (DUAIRQ) begin // CHECK ME !!!!
			IPL0n <= 1;
			IPL1n <= 1;
			IPL2n <= 0;
		end
		else if (IRQ2) begin
			IPL0n <= 1;
			IPL1n <= 0;
			IPL2n <= 1;
		end
		else begin // No IRQ
			IPL0n <= 1;
			IPL1n <= 1;
			IPL2n <= 1;
		end
	end
endmodule

// RESET IS A HACK !!!!

// Pin assignments for yosys flow
// Designed to be used with the little atf programmer for easy patching to test
//PIN: CHIP "rosco" ASSIGNED TO A PLCC84
// --
// These are a pain !
// -- A_HIGH[]
// 18=0 19=1 20=2 21=3 22=4 23=5
// A_HIGH_0  A18 18
// A_HIGH_1  A19 4
// A_HIGH_2  A20 9
// A_HIGH_3  A21 6
// A_HIGH_4  A22 11
// A_HIGH_5  A23 10
// -- A_MED[]
// 6=0 7=1 8=2 9=3 10=4 11=5 12=6 13=7 14=8 15=9 16=10
// A_MED_0  A6  24
// A_MED_1  A7  20
// A_MED_2  A8  12
// A_MED_3  A9  22
// A_MED_4  A10 15
// A_MED_5  A11 21
// A_MED_6  A12 2
// A_MED_7  A13 17
// A_MED_8  A14 5
// A_MED_9  A15 16
// A_MED_10 A16 8 
// -- A_LOW[]
// 0=3 1=2 2=1 3=0
// A_LOW_0  A3 25  
// A_LOW_1  A2 27 
// A_LOW_2  A1 28
// A_LOW_3  A0 29 
// --
//PIN: RESETn      : 1
//PIN: A_MED_6     : 2
//PIN: A_HIGH_1    : 4
//PIN: A_MED_8     : 5
//PIN: A_HIGH_3    : 6
// --  GND         : 7
//PIN: A_MED_10    : 8
//PIN: A_HIGH_2    : 9
//PIN: A_HIGH_5    : 10
//PIN: A_HIGH_4    : 11
//PIN: A_MED_2     : 12
// --  VCC         : 13
// --  TDI         : 14
//PIN: A_MED_4     : 15
//PIN: A_MED_9     : 16
//PIN: A_MED_7     : 17
//PIN: A_HIGH_0    : 18
// --  GND         : 19
//PIN: A_MED_1     : 20
//PIN: A_MED_5     : 21
//PIN: A_MED_3     : 22
// --  TMS         : 23
//PIN: A_MED_0     : 24
//PIN: A_LOW_0     : 25
// --  VCC         : 26
//PIN: A_LOW_1     : 27
//PIN: A_LOW_2     : 28
//PIN: A_LOW_3     : 29
//PIN: IRQ2        : 30
//PIN: IRQ3        : 31
// --  GND         : 32
//PIN: IRQ5        : 33
//PIN: IRQ6        : 34
//PIN: SIZ0        : 35
//PIN: LDSn        : 36
//PIN: SIZ1        : 37
// --  VCC         : 38
//PIN: UDSn        : 39
//PIN: RW          : 40
//PIN: EXPSELn     : 41
// --  GND         : 42
// --  VCC         : 43
//PIN: ODDROMSELn  : 44
//PIN: ODDRAMSELn  : 45
//PIN: EVENROMSELn : 46 
// --  GND         : 47
//PIN: EVENRAMSELn : 48
// --  X           : 49
//PIN: IOSELn      : 50
//PIN: WR          : 51
// --  X           : 52
// --  VCC         : 53
//PIN: DUASEL      : 54
//PIN: DUAIRQ      : 55
//PIN: DTACKn      : 56
//PIN: ESIG        : 57
// --  X           : 58
// --  GND         : 59
// --  X           : 60
//PIN: DSn         : 61
// --  TCK         : 62
// --  X           : 63
// --  X           : 64
//PIN: DUAIACKn    : 65
// --  VCC         : 66
//PIN: HALT        : 67
//PIN: RESET       : 68 
//PIN: RUNLED      : 69
//PIN: BERRn       : 70
// --  TDO         : 71
// --  GND         : 72
//PIN: FC_0        : 73
//PIN: FC_1        : 74
//PIN: FC_2        : 75
//PIN: HWRST       : 76
//PIN: ASn         : 77
// --  VCC         : 78
//PIN: IPL2        : 79
//PIN: IPL1        : 80
//PIN: IPL0        : 81
// --  GND         : 82
//PIN: CLK         : 83
// --  OE1_I       : 84