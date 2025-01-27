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

ADD IN THE 74148 CHIP !!!

	// Reconstruct the full address bus
	wire [23:0] A = {A_HIGH, 1'b0, A_MED, 2'b0, A_LOW};

	// GLUE 
	// Tri state is not well supported by yosys .. do not use these in any equations ...
	assign HALT = HWRST ? 1'b0 : 1'bZ;
	assign RESET = HWRST ? 1'b0 : 1'bZ;
	assign RUNLED =  HWRST; 
	
	wire cpusp_n = !(!HWRST && (FC[2:0] == 3'b111));
	assign DUIACKn = !((!HWRST && (FC[2:0] == 3'b111)) && !ASn && (A[19] == 1) && (A[3:1] == 3'b100)); 

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
	assign o_ODDROM_n = !(cpusp && !i_AS_n && !i_LDS_n && rom);
	assign o_EVENROM_n = !(cpusp && !i_AS_n && !i_UDS_n && rom);

	// RAM at 0x000000 (1 MB)
	wire ram = boot && (A[23:20] == 4'h0);
	assign o_ODDRAM_n = !(cpusp && !i_AS_n && !i_LDS_n && ram);
	assign o_EVENRAM_n = !(cpusp && !i_AS_n && !i_UDS_n && ram);
	
	// IO at 0xF00000 
	wire io = A[23:20] == 4'hF;
	assign o_IOSEL_n = !(cpusp && io);

	// Expansion at 0x100000 - 0xD00000
	wire exp = (A[23:20] >= 4'h1) && (A[23:20] <= 4'hD);
	assign o_EXPSEL_n = !(cpusp && !i_AS_n && exp);
	
	assign o_WR = !i_RW;

	assign PPDTACK = !o_EVENROM_n || !o_ODDROM_n || !o_EVENRAM_n || !o_ODDRAM_n || !o_EXPSEL_n;
	assign o_DTACK_n = PPDTACK ? 1'b0 : 1'bZ;


	// CPU GLUE
	assign o_UDS_n = !(!i_DS_n && !A[0]);
	assign o_LDS_n = !((!i_DS_n && !A[0]) || (!i_DS_n && !i_SIZ0) || (!i_DS_n && i_SIZ1));

	// set o_E
	// according the datasheet, a single period of clock E 
	// consists of 10 MC68000 clock periods (six clocks low, 4 clocks high)
	//
	// I dont understnad that 6/4 ?? .. will just count 10 cycles ..

	reg trigger = 1'b0;
	reg [3:0] counter;

	always @(posedge i_CLK) begin
		if (!i_RESET_n) begin
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

	assign o_E = trigger;


	// WATCHDOG
	// I think the original code is counting to 128 .. about 10ms on a 12MHz 68010
	
	reg pberr = 1'b0;
	reg [6:0] wdcounter;
	wire wden = !i_AS_n || (!i_CPUSP && A[19]);

	always @(posedge i_CLK) begin
		if (!wden) begin
			wdcounter <= 7'b0;
		end else if (wdcounter == 7'b1111111) begin
			pberr <= 1'b1;
		end else begin 
			wdcounter <= wdcounter + 1;
		end 
	end

	assign o_BERR_n = pberr ? 1'b0 : 1'bZ;

endmodule

// Pin assignments for yosys flow
// Designed to be used with the little atf programmer for easy patching to test
//PIN: CHIP "rosco" ASSIGNED TO AN PLCC84


// Change these !!
// 18=0 19=1 20=2 21=3 22=4 23=5
//PIN: i_A_0  : 41 
//PIN: i_A_1  : 39 
//PIN: i_A_2  : 37 
//PIN: i_A_3  : 34 
//PIN: i_A_4  : 12



//PIN: RESET      : 1
//PIN: A12        : 2
//PIN: A19        : 3
//PIN: A14        : 4
//PIN: A21        : 5
//PIN: A16        : 6
// --  GND        : 7
//PIN: A20        : 8
//PIN: A23        : 9
//PIN: A22        : 10
//PIN: A8         : 11
//PIN: A10        : 12
// --  VCC        : 13
// --  TDI        : 14
//PIN: A15        : 15
//PIN: A13        : 16
//PIN: A18        : 17
//PIN: A7         : 18
// --  GND        : 19
//PIN: A11        : 20
//PIN: A9         : 21
//PIN: A6         : 22
// --  TMS        : 23
//PIN: A3         : 24
//PIN: A2         : 25
// --  VCC        : 26
//PIN: A1         : 27
//PIN: A0         : 28
//PIN: IRQ2       : 29
//PIN: IRQ3       : 30
//PIN: IRQ5       : 31
// --  GND        : 32
//PIN: IRQ6       : 33
//PIN: SIZ0       : 34
//PIN: LDS        : 35
//PIN: SIZ1       : 36
//PIN: UDS        : 37
// --  VCC        : 38
//PIN: RW         : 39
// --  X          : 40
//PIN: EXPSEL     : 41
// --  GND        : 42
// --  VCC        : 43
// --  X          : 44
//PIN: EVENRAMSEL : 45
//PIN: ODDRAMSEL  : 46
// --  GND        : 47
//PIN: EVENROMSEL : 48
//PIN: ODDROMSEL  : 49
//PIN: IOSEL      : 50
//PIN: WR         : 51
// --  X          : 52
// --  VCC        : 53
//PIN: DTACK      : 54
//PIN: DUAIRQ     : 55
//PIN: DUASEL     : 56
//PIN: E          : 57
// --  X          : 58
// --  GND        : 59
// --  X          : 60
//PIN: DS         : 61
// --  TCK        : 62
// --  X          : 63
// --  X          : 64
//PIN: DUAIACK    : 65
// --  VCC        : 66
//PIN: HALT       : 67
// --  RESET      : 68
//PIN: RUNLED     : 69
//PIN: BERR       : 70
// --  TDO        : 71
// --  GND        : 72
//PIN: FC0        : 73
//PIN: FC1        : 74
//PIN: FC2        : 75
//PIN: HWRST      : 76
//PIN: AS         : 77
// --  VCC        : 78
//PIN: IPL2       : 79
//PIN: IPL1       : 80
//PIN: IPL0       : 81
// --  GND        : 82
//PIN: CLK        : 83
// --  OE1_I      : 84


