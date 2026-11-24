/*
* Copyright 2019 ETH Zürich and University of Bologna
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

.section .vectors, "ax"
.option norvc
vector_table:
	//  0 : exception Handler and user software interrupt
	j handler_exception
	//  1 : supervisor software interrupt
	j __no_irq_handler
	//  2 : unmapped
	j __no_irq_handler
	//  3 : machine software interrupt handler
	j handler_irq_software
	//  4 : user timer interrupt
	j __no_irq_handler
	//  5 : supervisor timer interrupt
	j __no_irq_handler
	//  6 : unmapped
	j __no_irq_handler
	//  7 : machine timer interrupt handler
	j handler_irq_timer
	//  8 : user external interrupt
	j __no_irq_handler
	//  9 : supervisor external interrupt
	j __no_irq_handler
	// 10 : unmapped
	j __no_irq_handler
	// 11 : machine external interrupt handler
	j handler_irq_external
	// 12 : unmapped
	j __no_irq_handler
	// 13 : unmapped
	j __no_irq_handler
	// 14 : unmapped
	j __no_irq_handler
	// 15 : unmapped
	j __no_irq_handler
	// 16-31 : local interrupts, not implemented by CVA6
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler
	j __no_irq_handler


.section .text.vecs
/* exception handling */
.globl __no_irq_handler
__no_irq_handler:
	/*
	REMOVING THIS CALL REDUCES CODE SIZE CONSIDERABLY
	This will not print an error message in case of not finding
	the proper handler to manage an interrupt.
	la a0, no_exception_handler_msg
	jal ra, puts
	*/
	j __no_irq_handler

/*
THESE STRINGS ARE NOT LONGER NEEDED
Only the last two were used, and their
call was removed to reduce base code size
.section .rodata
illegal_insn_msg:
	.string "illegal instruction exception handler entered\n"
ecall_msg:
	.string "ecall exception handler entered\n"
ebreak_msg:
	.string "ebreak exception handler entered\n"
unknown_msg:
	.string "unknown exception handler entered\n"
no_exception_handler_msg:
	.string "no exception handler installed\n"
*/