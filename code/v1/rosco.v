// rosco logic in verilog
// Malcolm Harrow, January 2025
// MIT License

// Memory map:
// * Onboard RAM    : $00000000 - $000FFFFF (1MB)
// * Expansion space: $00100000 - $00DFFFFF (13MB)
// * ROM            : $00E00000 - $00EFFFFF (1MB)
// * IO             : $00F00000 - $FFFFFFFF (1MB)

`default_nettype none

module rosco (
	input  CLK, RESETn,
	input  [23:18] A_HIGH,
	input  [16:6] A_MED,
	input  [3:0] A_LOW,
    input  IRQ2, IRQ3, IRQ5, IRQ6,
	input  SIZ0, SIZ1,
	input  RW,
	input  [2:0] FC,
    input  DSn,
    input  ASn,
	input  DUAIRQn,     
	input  HWRST,
	inout  DTACKn,
	inout  HALT,
	inout  BERRn,
	output WR,
	output LDSn, UDSn,
	output EXPSELn, EVENRAMSELn, ODDRAMSELn, EVENROMSELn, ODDROMSELn, IOSELn, DUASELn,
	output reg E,
	output ILP0, ILP1, ILP2,
	output DUAIACKn,
	output RUNLED,

	output PPDTACK,  // has to be an output for the tri-state logic to work
);

// HACK !!!ADD IN THE 74148 CHIP !!!

	// Reconstruct the full address bus
	wire [23:0] A = {A_HIGH, 1'b0, A_MED, 2'b0, A_LOW};

	// GLUE 
	// Tri state is not well supported by yosys .. do not use these in any equations ...
	assign HALT = HWRST ? 1'b0 : 1'bZ;
	assign RESETn = HWRST ? 1'b0 : 1'bZ;
	assign RUNLED =  HWRST; 
	
	wire cpucp_n = !(!HWRST && (FC[2:0] == 3'b111));
	assign DUAIACKn = !((!HWRST && (FC[2:0] == 3'b111)) && !ASn && (A[19] == 1) && (A[3:1] == 3'b100)); 

	// Count AS (memory access) cycles to set BOOT for the first 4 memory reads
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


	// DUART SELECT
	assign DUASELn = !(A[19:6] == 0 && !LDSn && !IOSELn);


	// ADDRESS DECODER
	// ROM at 0xE00000 - (0x000000 on BOOT)
	wire rom = !boot || A[23:20] == 4'hE;
	assign ODDROMSELn = !(cpucp_n && !ASn && !LDSn && rom);
	assign EVENROMSELn = !(cpucp_n && !ASn && !UDSn && rom);

	// RAM at 0x000000 (1 MB)
	wire ram = boot && (A[23:20] == 4'h0);
	assign ODDRAMSELn = !(cpucp_n && !ASn && !LDSn && ram);
	assign EVENRAMSELn = !(cpucp_n && !ASn && !UDSn && ram);
	
	// IO at 0xF00000 
	wire io = A[23:20] == 4'hF;
	assign IOSELn = !(cpucp_n && io);

	// Expansion at 0x100000 - 0xD00000
	wire exp = (A[23:20] >= 4'h1) && (A[23:20] <= 4'hD);
	assign EXPSELn = !(cpucp_n && !ASn && exp);
	
	assign WR = !RW;

	assign PPDTACK = !EVENROMSELn || !ODDROMSELn || !EVENRAMSELn || !ODDRAMSELn || !EXPSELn;
	assign DTACKn = PPDTACK ? 1'b0 : 1'bZ;


	// CPU GLUE
	assign UDSn = !(!DSn && !A[0]);
	assign LDSn = !((!DSn && !A[0]) || (!DSn && !SIZ0) || (!DSn && SIZ1));

	// set o_E
	// according the datasheet, a single period of clock E 
	// consists of 10 MC68000 clock periods (six clocks low, 4 clocks high)
	//
	// I dont understnad that 6/4 ?? .. will just count 10 cycles ..

	reg trigger = 1'b0;
	reg [3:0] counter;

	always @(posedge CLK) begin
		if (!RESETn) begin
			counter <= 4'b0;
			trigger <= 1'b0;
		end else if (counter == 10) begin
			counter <= 4'b0;
			trigger <= 1'b1;
		end else begin 
			counter <= counter + 1;
			trigger <= 1'b0;
		end 
	end

	assign E = trigger;


	// WATCHDOG
	// I think the original code is counting to 128 .. about 10ms on a 12MHz 68010
	
	reg pberr = 1'b0;
	reg [6:0] wdcounter;
	wire wden = !ASn || (!cpucp_n && A[19]);

	always @(posedge CLK) begin
		if (!wden) begin
			wdcounter <= 7'b0;
		end else if (wdcounter == 7'b1111111) begin
			pberr <= 1'b1;
		end else begin 
			wdcounter <= wdcounter + 1;
		end 
	end

	assign BERRn = pberr ? 1'b0 : 1'bZ;

endmodule

// Pin assignments for yosys flow
// Designed to be used with the little atf programmer for easy patching to test
//PIN: CHIP "rosco" ASSIGNED TO AN PLCC84
// --
// These are a pain !
// -- A_HIGH[]
// 18=0 19=1 20=2 21=3 22=4 23=5
// A_HIGH_0  A18 17
// A_HIGH_1  A19 3 
// A_HIGH_2  A20 8 
// A_HIGH_3  A21 5
// A_HIGH_4  A22 10
// A_HIGH_5  A23 9
// -- A_MED[]
// 6=0 7=1 8=2 9=3 10=4 11=5 12=6 13=7 14=8 15=9 16=10
// A_MED_0  A6  22
// A_MED_1  A7  18
// A_MED_2  A8  11
// A_MED_3  A9  21
// A_MED_4  A10 12
// A_MED_5  A11 20
// A_MED_6  A12 2
// A_MED_7  A13 16
// A_MED_8  A14 4
// A_MED_9  A15 15
// A_MED_10 A16 6 
// -- A_LOW[]
// 0=3 1=2 2=1 3=0
// A_LOW_0  A3 24  
// A_LOW_1  A2 25 
// A_LOW_2  A1 27
// A_LOW_3  A0 28 
// --
//PIN: RESETn      : 1
//PIN: A_MED_6     : 2
//PIN: A_HIGH_1    : 3
//PIN: A_MED_8     : 4
//PIN: A_HIGH_3    : 5
//PIN: A_MED_10    : 6
// --  GND         : 7
//PIN: A_HIGH_2    : 8
//PIN: A_HIGH_5    : 9
//PIN: A_HIGH_4    : 10
//PIN: A_MED_2     : 11
//PIN: A_MED_4     : 12
// --  VCC         : 13
// --  TDI         : 14
//PIN: A_MED_9     : 15
//PIN: A_MED_7     : 16
//PIN: A_HIGH_0    : 17
//PIN: A_MED_1     : 18
// --  GND         : 19
//PIN: A_MED_5     : 20
//PIN: A_MED_3     : 21
//PIN: A_MED_0     : 22
// --  TMS         : 23
//PIN: A_LOW_0     : 24
//PIN: A_LOW_1     : 25
// --  VCC         : 26
//PIN: A_LOW_2     : 27
//PIN: A_LOW_3     : 28
//PIN: IRQ2        : 29
//PIN: IRQ3        : 30
//PIN: IRQ5        : 31
// --  GND         : 32
//PIN: IRQ6        : 33
//PIN: SIZ0        : 34
//PIN: LDSn        : 35
//PIN: SIZ1        : 36
//PIN: UDSn        : 37
// --  VCC         : 38
//PIN: RW          : 39
// --  X           : 40
//PIN: EXPSELn     : 41
// --  GND         : 42
// --  VCC         : 43
// --  X           : 44
//PIN: EVENRAMSELn : 45
//PIN: ODDRAMSELn  : 46
// --  GND         : 47
//PIN: EVENROMSELn : 48
//PIN: ODDROMSELn  : 49
//PIN: IOSELn      : 50
//PIN: WR          : 51
// --  X           : 52
// --  VCC         : 53
//PIN: DTACKn      : 54
//PIN: DUAIRQ      : 55
//PIN: DUASEL      : 56
//PIN: E           : 57
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
// --  RESET       : 68
//PIN: RUNLED      : 69
//PIN: BERRn       : 70
// --  TDO         : 71
// --  GND         : 72
//PIN: FC_2        : 73
//PIN: FC_1        : 74
//PIN: FC_0        : 75
//PIN: HWRST       : 76
//PIN: AS          : 77
// --  VCC         : 78
//PIN: IPL2        : 79
//PIN: IPL1        : 80
//PIN: IPL0        : 81
// --  GND         : 82
//PIN: CLK         : 83
// --  OE1_I       : 84