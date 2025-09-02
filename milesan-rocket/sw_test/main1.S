  .section ".text.init","ax",@progbits
  .globl _start
  .align 2
_start:
li a3, 291
li a7, -1954
li s10, 201
li t6, 477
csrwi mcycle, 0
divuw t5, a7, t6
remuw t3, s10, a3
csrr ra, mcycle
li a0, 0x60000010
sd ra, 0(a0)
li a0, 0x60000000
sd a0, 0(a0)