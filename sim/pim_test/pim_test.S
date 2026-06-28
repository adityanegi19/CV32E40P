# =============================================================================
# pim_test.S  --  CV32E40P PIM Extension Assembly Test
# =============================================================================
#
# Tests add.p and mul.p custom PIM instructions by:
#   1. Loading SRAM base address (0x20000000) into x5
#   2. Initialising five 32-bit words in SRAM (word offsets 0–4)
#   3. Executing add.p x10, x5, imm1=1, imm2=2  (expects 3+7 = 10)
#   4. Executing mul.p x11, x5, imm1=3, imm2=4  (expects 4*2 = 8)
#   5. Storing results at word offsets 5 and 6
#   6. Writing done sentinel 0xDEAD at word offset 7
#   7. Entering an infinite loop
#
# SRAM byte-address map (base 0x20000000):
#   +0x00  word 0 : 5         (operand initialisation)
#   +0x04  word 1 : 3         (add.p operand A)
#   +0x08  word 2 : 7         (add.p operand B)
#   +0x0C  word 3 : 4         (mul.p operand A)
#   +0x10  word 4 : 2         (mul.p operand B)
#   +0x14  word 5 : add.p result (expected 10, written here by sw)
#   +0x18  word 6 : mul.p result (expected  8, written here by sw)
#   +0x1C  word 7 : done sentinel 0x0000DEAD
#
# =============================================================================
# PIM INSTRUCTION ENCODING  (both use OPCODE_LOAD = 7'b0000011)
# =============================================================================
#
#  I-type bit-field layout:
#    [31:26]  imm6_1  -- 6-bit signed word offset to operand A in SRAM
#    [25:20]  imm6_2  -- 6-bit signed word offset to operand B in SRAM
#    [19:15]  rs1     -- base-address register (holds SRAM byte address)
#    [14:12]  funct3  -- 3'b011 = add.p  |  3'b110 = mul.p
#    [11:7]   rd      -- destination register (receives PIM result)
#    [6:0]    opcode  -- 7'b0000011 (LOAD)
#
#  Macro formula:
#    .word = ((imm1 & 0x3F) << 26)
#          | ((imm2 & 0x3F) << 20)
#          | (rs1_num        << 15)
#          | (funct3         << 12)
#          | (rd_num         <<  7)
#          | 0x03
# =============================================================================

# ---------------------------------------------------------------------------
# PIM Instruction Macros
#   Arguments are raw register numbers (e.g. 10 for x10) and integer immediates.
# ---------------------------------------------------------------------------

.macro PIM_ADD_P rd_num, rs1_num, imm1, imm2
    # add.p rd, rs1, imm1, imm2  (funct3 = 3'b011 = 3)
    # Result written into rd = SRAM[rs1 + imm1*4] + SRAM[rs1 + imm2*4]
    .word ((\imm1 & 0x3F) << 26) | ((\imm2 & 0x3F) << 20) | (\rs1_num << 15) | (0x3 << 12) | (\rd_num << 7) | 0x03
.endm

.macro PIM_MUL_P rd_num, rs1_num, imm1, imm2
    # mul.p rd, rs1, imm1, imm2  (funct3 = 3'b110 = 6)
    # Result written into rd = SRAM[rs1 + imm1*4] * SRAM[rs1 + imm2*4]
    .word ((\imm1 & 0x3F) << 26) | ((\imm2 & 0x3F) << 20) | (\rs1_num << 15) | (0x6 << 12) | (\rd_num << 7) | 0x03
.endm

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
.equ SRAM_BASE,      0x20000000
.equ RES_ADD_OFFSET, 20          # byte offset for add.p result  (word 5)
.equ RES_MUL_OFFSET, 24          # byte offset for mul.p result  (word 6)
.equ DONE_OFFSET,    28          # byte offset for done sentinel  (word 7)
.equ DONE_VAL,       0xDEAD      # sentinel value written when test completes

# ---------------------------------------------------------------------------
# Text section — placed at 0x00000000 by link.ld
# ---------------------------------------------------------------------------
.section .text
.globl _start

_start:

    # =========================================================================
    # Step 1: Load SRAM base address into x5
    #   lui x5, 0x20000  →  x5 = (0x20000 << 12) = 0x20000000
    # =========================================================================
    lui   x5, 0x20000           # x5 = 0x20000000 (SRAM base)

    # =========================================================================
    # Step 2: Initialise five consecutive 32-bit words in SRAM
    #   Values chosen so PIM results are unambiguous and easy to verify.
    # =========================================================================
    li    x6, 5
    sw    x6, 0(x5)             # SRAM[0x20000000] = 5  (word 0, unused by PIM)

    li    x6, 3
    sw    x6, 4(x5)             # SRAM[0x20000004] = 3  (word 1, add.p operand A)

    li    x6, 7
    sw    x6, 8(x5)             # SRAM[0x20000008] = 7  (word 2, add.p operand B)

    li    x6, 4
    sw    x6, 12(x5)            # SRAM[0x2000000C] = 4  (word 3, mul.p operand A)

    li    x6, 2
    sw    x6, 16(x5)            # SRAM[0x20000010] = 2  (word 4, mul.p operand B)

    # =========================================================================
    # Step 3: add.p  x10, x5, imm1=1, imm2=2
    #
    #   The PCU reads pim_imm1=1 and pim_imm2=2.
    #   SRAM controller computes:
    #     word_addr_A = pim_base_addr[20:2] + sign_ext(1) = 0 + 1 = 1
    #     word_addr_B = pim_base_addr[20:2] + sign_ext(2) = 0 + 2 = 2
    #     result = mem_array[1] + mem_array[2] = 3 + 7 = 10
    #   Expected: x10 = 10
    #
    #   Encoding (verified):
    #     [31:26] = 000001  (imm6_1 = 1)
    #     [25:20] = 000010  (imm6_2 = 2)
    #     [19:15] = 00101   (rs1 = x5 = 5)
    #     [14:12] = 011     (funct3 = add.p)
    #     [11:7]  = 01010   (rd = x10 = 10)
    #     [6:0]   = 0000011 (LOAD opcode)
    #
    #   Binary  : 0000_0100_0010_0010_1011_0101_0000_0011
    #   Hex     : 0x0422_B503
    #
    #   OBI address = rs1 + sign_ext({imm6_1, imm6_2})
    #               = 0x20000000 + sign_ext(12'b000001_000010)
    #               = 0x20000000 + 66 = 0x20000042  (within SRAM window ✓)
    # =========================================================================
    PIM_ADD_P 10, 5, 1, 2       # x10 = add.p result = 10  (.word 0x0422B503)

    # =========================================================================
    # Step 4: mul.p  x11, x5, imm1=3, imm2=4
    #
    #   The PCU reads pim_imm1=3 and pim_imm2=4.
    #   SRAM controller computes:
    #     word_addr_A = 0 + 3 = 3
    #     word_addr_B = 0 + 4 = 4
    #     result = mem_array[3] * mem_array[4] = 4 * 2 = 8
    #   Expected: x11 = 8
    #
    #   Encoding (verified):
    #     [31:26] = 000011  (imm6_1 = 3)
    #     [25:20] = 000100  (imm6_2 = 4)
    #     [19:15] = 00101   (rs1 = x5 = 5)
    #     [14:12] = 110     (funct3 = mul.p)
    #     [11:7]  = 01011   (rd = x11 = 11)
    #     [6:0]   = 0000011 (LOAD opcode)
    #
    #   Binary  : 0000_1100_0100_0010_1110_0101_1000_0011
    #   Hex     : 0x0C42_E583
    #
    #   OBI address = 0x20000000 + sign_ext(12'b000011_000100)
    #               = 0x20000000 + 196 = 0x200000C4  (within SRAM window ✓)
    # =========================================================================
    PIM_MUL_P 11, 5, 3, 4       # x11 = mul.p result = 8   (.word 0x0C42E583)

    # =========================================================================
    # Step 5: Store results to SRAM results area (words 5 and 6)
    # =========================================================================
    sw    x10, 20(x5)           # SRAM[0x20000014] = x10 (add.p result, expect 10)
    sw    x11, 24(x5)           # SRAM[0x20000018] = x11 (mul.p result, expect  8)

    # =========================================================================
    # Step 6: Write done sentinel — testbench polls word 7 for this value
    # =========================================================================
    li    x12, 0xDEAD
    sw    x12, 28(x5)           # SRAM[0x2000001C] = 0xDEAD (done sentinel)

    # =========================================================================
    # Step 7: Infinite loop — core stays here after test completes
    # =========================================================================
done_loop:
    j     done_loop
