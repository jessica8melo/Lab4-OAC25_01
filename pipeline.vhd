-- Pipeline de 5 estágios.
-- Sem adiantamento ou detecção de hazards.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.riscv_pkg.all;

entity Pipeline is
    port (
        clockCPU : in  std_logic;
        clockMem : in  std_logic;
        reset    : in  std_logic;
        PC       : out std_logic_vector(31 downto 0);
        Instr    : out std_logic_vector(31 downto 0);
        regin    : in  std_logic_vector(4 downto 0);
        regout   : out std_logic_vector(31 downto 0)
    );
end Pipeline;

architecture Behavioral of Pipeline is

    -- Mesmos componenetes do Uniciclo
    component ControlUnit is
        port (
            opcode      : in  STD_LOGIC_VECTOR (6 downto 0);
            zero_flag   : in  STD_LOGIC; -- Para determinar PCSrc
            ALUOpType   : out STD_LOGIC_VECTOR(1 downto 0);
            RegWrite    : out STD_LOGIC;
            MemRead     : out STD_LOGIC;
            MemWrite    : out STD_LOGIC;
            ALUSrc      : out STD_LOGIC;
            WBDataSel   : out STD_LOGIC_VECTOR(1 downto 0);
            BranchPCSel : out STD_LOGIC;
            Jump        : out STD_LOGIC
        );
    end component;

    component xregs is
        generic (
            SIZE : natural := 32;
            ADDR : natural := 5
        );
        port (
            iCLK  : in  std_logic;
            iRST  : in  std_logic;
            iWREN : in  std_logic;
            iRS1  : in  std_logic_vector(ADDR-1 downto 0);
            iRS2  : in  std_logic_vector(ADDR-1 downto 0);
            iRD   : in  std_logic_vector(ADDR-1 downto 0);
            iDATA : in  std_logic_vector(SIZE-1 downto 0);
            oREGA : out std_logic_vector(SIZE-1 downto 0);
            oREGB : out std_logic_vector(SIZE-1 downto 0);
            iDISP : in  std_logic_vector(ADDR-1 downto 0);
            oREGD : out std_logic_vector(SIZE-1 downto 0)
        );
    end component;

    component ALUControl is
        port (
            ALUOpType : in  STD_LOGIC_VECTOR (1 downto 0);
            funct3    : in  STD_LOGIC_VECTOR (2 downto 0);
            funct7    : in  STD_LOGIC;
            ALUCtrl   : out STD_LOGIC_VECTOR (4 downto 0)
        );
    end component;

    component ALU is
        port (
            iControl : in  std_logic_vector(4 downto 0):="00000";
            iA       : in  std_logic_vector(31 downto 0);
            iB       : in  std_logic_vector(31 downto 0);
            oResult  : out std_logic_vector(31 downto 0)
        );
    end component;

    component genImm32 is
        port (
            instr : in  std_logic_vector(31 downto 0);
            imm32 : out std_logic_vector(31 downto 0)
        );
    end component;
   
    -- Sinal de seleção do PC
    signal PCSrc         : std_logic;

    -- Estágio Instruction Fetch (IF)
    signal PC_reg        : std_logic_vector(31 downto 0) := TEXT_ADDRESS;
    signal PC_next       : std_logic_vector(31 downto 0);
    signal PC_plus_4_IF  : std_logic_vector(31 downto 0);
    signal Instr_IF      : std_logic_vector(31 downto 0);

    -- Registrador de IF/ID (Ins Decode)
    signal IF_ID_Instr     : std_logic_vector(31 downto 0);
    signal IF_ID_PC_plus_4 : std_logic_vector(31 downto 0);
   
    -- Estágio ID
    signal ID_ReadData1    : std_logic_vector(31 downto 0);
    signal ID_ReadData2    : std_logic_vector(31 downto 0);
    signal ID_Imm          : std_logic_vector(31 downto 0);
   
    -- Registrador de Pipeline ID/EX (Ins Execute)
    signal ID_EX_RegWrite    : std_logic;
    signal ID_EX_MemRead     : std_logic;
    signal ID_EX_MemWrite    : std_logic;
    signal ID_EX_ALUSrc      : std_logic;
    signal ID_EX_WBDataSel   : std_logic_vector(1 downto 0);
    signal ID_EX_ALUOpType   : std_logic_vector(1 downto 0);
    signal ID_EX_Jump        : std_logic;
    signal ID_EX_BranchPCSel : std_logic;
    signal ID_EX_ReadData1   : std_logic_vector(31 downto 0);
    signal ID_EX_ReadData2   : std_logic_vector(31 downto 0);
    signal ID_EX_Imm         : std_logic_vector(31 downto 0);
    signal ID_EX_rd          : std_logic_vector(4 downto 0);
    signal ID_EX_funct3      : std_logic_vector(2 downto 0);
    signal ID_EX_funct7_5    : std_logic;
    signal ID_EX_PC_plus_4   : std_logic_vector(31 downto 0);

    -- Estágio EX
    signal EX_ALU_B_Mux_Out  : std_logic_vector(31 downto 0);
    signal EX_ALUResult      : std_logic_vector(31 downto 0);
    signal EX_ZeroFlag       : std_logic;
    signal Branch_Target_Addr: std_logic_vector(31 downto 0);
   
    -- Registrador de Pipeline EX/MEM (Memory Access)
    signal EX_MEM_RegWrite     : std_logic;
    signal EX_MEM_MemRead      : std_logic;
    signal EX_MEM_MemWrite     : std_logic;
    signal EX_MEM_WBDataSel    : std_logic_vector(1 downto 0);
    signal EX_MEM_ALUResult    : std_logic_vector(31 downto 0);
    signal EX_MEM_WriteData    : std_logic_vector(31 downto 0);
    signal EX_MEM_rd           : std_logic_vector(4 downto 0);
    signal EX_MEM_ZeroFlag     : std_logic;
    signal EX_MEM_BranchPCSel  : std_logic;
    signal EX_MEM_Jump         : std_logic;
    signal EX_MEM_PC_plus_4    : std_logic_vector(31 downto 0);
    signal EX_MEM_JALR_Addr    : std_logic_vector(31 downto 0);


    -- Estágio MEM
    signal MEM_ReadDataMem : std_logic_vector(31 downto 0);
    signal PC_Target       : std_logic_vector(31 downto 0);

    -- Registrador de Pipeline MEM/WB (Write Back)
    signal MEM_WB_RegWrite    : std_logic;
    signal MEM_WB_WBDataSel   : std_logic_vector(1 downto 0);
    signal MEM_WB_ReadDataMem : std_logic_vector(31 downto 0);
    signal MEM_WB_ALUResult   : std_logic_vector(31 downto 0);
    signal MEM_WB_rd          : std_logic_vector(4 downto 0);
    signal MEM_WB_PC_plus_4   : std_logic_vector(31 downto 0);
   
    -- Estágio WB
    signal WB_WriteData : std_logic_vector(31 downto 0);

 -- Sinais Intermediários
    signal CU_ALUOpType   : std_logic_vector(1 downto 0);
    signal CU_RegWrite    : std_logic;
    signal CU_MemRead     : std_logic;
    signal CU_MemWrite    : std_logic;
    signal CU_ALUSrc      : std_logic;
    signal CU_WBDataSel   : std_logic_vector(1 downto 0);
    signal CU_BranchPCSel : std_logic;
    signal CU_Jump        : std_logic;

begin
    -- Atribuição de saídas para depuração
    PC    <= PC_reg;
    Instr <= IF_ID_Instr;
   
    -- ESTÁGIO IF (INSTRUCTION FETCH)
    PC_plus_4_IF <= std_logic_vector(unsigned(PC_reg) + 4);

    -- MUX para selecionar o próximo PC. A decisão é tomada no estágio MEM.
    PC_Target <= EX_MEM_JALR_Addr when (EX_MEM_Jump = '1' and EX_MEM_rd = "00001" and EX_MEM_BranchPCSel = '1') -- JALR especifico (opcode+funct3)
                 else Branch_Target_Addr; -- JAL, BEQ

    PCSrc <= (EX_MEM_BranchPCSel and EX_MEM_ZeroFlag) or (EX_MEM_Jump);
   
    PC_next <= PC_Target when PCSrc = '1' else
               PC_plus_4_IF;

    -- PC
    process(clockCPU, reset)
    begin
        if reset = '1' then
            PC_reg <= TEXT_ADDRESS;
        elsif rising_edge(clockCPU) then
            PC_reg <= PC_next;
        end if;
    end process;
   
    -- Busca a Instrução
    MemI_inst : ramI
        port map (
            address => PC_reg(11 downto 2),
            clock   => clockMem,
            data    => (others => '0'),
            wren    => '0',
            q       => Instr_IF
        );
       
    -- REGISTRADOR DE IF/ID
    process(clockCPU, reset)
    begin
        if reset = '1' then
            IF_ID_Instr     <= (others => '0');
            IF_ID_PC_plus_4 <= (others => '0');
        elsif rising_edge(clockCPU) then
            -- Se PCSrc foi 1 no ciclo anterior, esta instrução é inválida.
            -- O hardware não faz flush. É nesses casos que vamos inserir NOPs
            IF_ID_Instr     <= Instr_IF;
            IF_ID_PC_plus_4 <= PC_plus_4_IF;
        end if;
    end process;
   
    -- ESTÁGIO ID (INSTRUCTION DECODE)
    -- Unidade de Controle Principal (sinais gerados a partir da instrução em ID)
    CU_inst : ControlUnit
        port map (
            opcode      => IF_ID_Instr(6 downto 0),
            zero_flag   => '0', -- A flag real só é conhecida em EX/MEM
            ALUOpType   => open,
            RegWrite    => open,
            MemRead     => open,
            MemWrite    => open,
            ALUSrc      => open,
            WBDataSel   => open,
            BranchPCSel => open,
            Jump        => open
        );
 
    -- Usado para passar os sinais de controle para o próximo estágio
    CU_inst_ID_EX : ControlUnit
        port map (
            opcode      => IF_ID_Instr(6 downto 0),
            zero_flag   => '0',
            ALUOpType   => CU_ALUOpType,
            RegWrite    => CU_RegWrite,
            MemRead     => CU_MemRead,
            MemWrite    => CU_MemWrite,
            ALUSrc      => CU_ALUSrc,
            WBDataSel   => CU_WBDataSel,
            BranchPCSel => CU_BranchPCSel,
            Jump        => CU_Jump
        );
       
    -- Banco de Regs (leitura em ID, escrita em WB)
    Regs_inst : xregs
        port map (
            iCLK  => clockCPU,
            iRST  => reset,
            iWREN => MEM_WB_RegWrite,       -- Sinal vem do estágio WB
            iRS1  => IF_ID_Instr(19 downto 15),
            iRS2  => IF_ID_Instr(24 downto 20),
            iRD   => MEM_WB_rd,             -- Endereço vem do estágio WB
            iDATA => WB_WriteData,          -- Dado vem do estágio WB
            oREGA => ID_ReadData1,
            oREGB => ID_ReadData2,
            iDISP => regin,
            oREGD => regout
        );

    -- Gerador de Imediato
    ImmGen_inst : genImm32
        port map (
            instr => IF_ID_Instr,
            imm32 => ID_Imm
        );
   
    -- REGISTRADOR DE ID/EX
    process(clockCPU, reset)
    begin
        if reset = '1' then
            ID_EX_RegWrite <= '0';
            ID_EX_MemRead <= '0';
            ID_EX_MemWrite <= '0';
            ID_EX_ALUSrc <= '0';
            ID_EX_WBDataSel <= "00";
            ID_EX_ALUOpType <= "00";
            ID_EX_Jump <= '0';
            ID_EX_BranchPCSel <= '0';
        elsif rising_edge(clockCPU) then
            -- Passa os sinais de controle para o próximo estágio
            ID_EX_RegWrite <= CU_RegWrite;
            ID_EX_MemRead <= CU_MemRead;
            ID_EX_MemWrite <= CU_MemWrite;
            ID_EX_ALUSrc <= CU_ALUSrc;
            ID_EX_WBDataSel <= CU_WBDataSel;
            ID_EX_ALUOpType <= CU_ALUOpType;
            ID_EX_Jump <= CU_Jump;
            ID_EX_BranchPCSel <= CU_BranchPCSel;
           
            -- Passa os dados
            ID_EX_ReadData1   <= ID_ReadData1;
            ID_EX_ReadData2   <= ID_ReadData2;
            ID_EX_Imm         <= ID_Imm;
            ID_EX_rd          <= IF_ID_Instr(11 downto 7);
            ID_EX_funct3      <= IF_ID_Instr(14 downto 12);
            ID_EX_funct7_5    <= IF_ID_Instr(30);
            ID_EX_PC_plus_4   <= IF_ID_PC_plus_4;
        end if;
    end process;

    -- ESTÁGIO EX (EXECUTE)
    -- MUX para selecionar o segundo operando da ULA (Registrador ou Imediato)
    EX_ALU_B_Mux_Out <= ID_EX_Imm when ID_EX_ALUSrc = '1' else ID_EX_ReadData2;

    -- Controle da ULA
    ALUCtrl_inst : ALUControl
        port map (
            ALUOpType => ID_EX_ALUOpType,
            funct3    => ID_EX_funct3,
            funct7    => ID_EX_funct7_5,
            ALUCtrl   => open
        );

    -- ULA
    ALU_inst : ALU
        port map (
            iControl => open,
            iA       => ID_EX_ReadData1,
            iB       => EX_ALU_B_Mux_Out,
            oResult  => EX_ALUResult
        );
       
    -- Flag Zero para branches
    EX_ZeroFlag <= '1' when (signed(ID_EX_ReadData1) - signed(ID_EX_ReadData2)) = 0 else '0';

    -- Endereço de desvio (JAL, BEQ)
    Branch_Target_Addr <= std_logic_vector(signed(ID_EX_PC_plus_4) - 4 + signed(ID_EX_Imm));

    -- REGISTRADOR DE EX/MEM
    process(clockCPU, reset)
    begin
        if reset = '1' then
            EX_MEM_RegWrite <= '0';
            EX_MEM_MemRead  <= '0';
            EX_MEM_MemWrite <= '0';
            EX_MEM_WBDataSel <= "00";
            EX_MEM_rd <= "00000";
            EX_MEM_Jump <= '0';
            EX_MEM_BranchPCSel <= '0';
        elsif rising_edge(clockCPU) then
            -- Passa sinais de controle
            EX_MEM_RegWrite    <= ID_EX_RegWrite;
            EX_MEM_MemRead     <= ID_EX_MemRead;
            EX_MEM_MemWrite    <= ID_EX_MemWrite;
            EX_MEM_WBDataSel   <= ID_EX_WBDataSel;
            EX_MEM_Jump        <= ID_EX_Jump;
            EX_MEM_BranchPCSel <= ID_EX_BranchPCSel;
           
            -- Passa dados
            EX_MEM_ALUResult   <= EX_ALUResult;
            EX_MEM_WriteData   <= ID_EX_ReadData2; -- Dado para SW
            EX_MEM_rd          <= ID_EX_rd;
            EX_MEM_ZeroFlag    <= EX_ZeroFlag;
            EX_MEM_PC_plus_4   <= ID_EX_PC_plus_4;
            EX_MEM_JALR_Addr   <= std_logic_vector(unsigned(EX_ALUResult) and x"FFFFFFFE");
        end if;
    end process;

    -- ESTÁGIO MEM (MEMORY ACCESS)
    MemD_inst : ramD
        port map (
            address => EX_MEM_ALUResult(11 downto 2),
            clock   => clockMem,
            data    => EX_MEM_WriteData,
            wren    => EX_MEM_MemWrite,
            q       => MEM_ReadDataMem
        );
       
    -- REGISTRADOR DE MEM/WB
    process(clockCPU, reset)
    begin
        if reset = '1' then
           MEM_WB_RegWrite <= '0';
           MEM_WB_WBDataSel <= "00";
           MEM_WB_rd <= "00000";
        elsif rising_edge(clockCPU) then
            -- Passa sinais de controle
            MEM_WB_RegWrite  <= EX_MEM_RegWrite;
            MEM_WB_WBDataSel <= EX_MEM_WBDataSel;
           
            -- Passa dados
            MEM_WB_ReadDataMem <= MEM_ReadDataMem;
            MEM_WB_ALUResult   <= EX_MEM_ALUResult;
            MEM_WB_rd          <= EX_MEM_rd;
            MEM_WB_PC_plus_4   <= EX_MEM_PC_plus_4;
        end if;
    end process;
   
    -- ESTÁGIO WB (WRITE BACK)
    -- MUX para selecionar o dado a ser escrito no banco de registradores
    with MEM_WB_WBDataSel select
        WB_WriteData <= MEM_WB_ALUResult   when WB_ALU,
                        MEM_WB_ReadDataMem when WB_MEM,
                        MEM_WB_PC_plus_4   when WB_PC4,
                        (others => '0')    when others;
end Behavioral;