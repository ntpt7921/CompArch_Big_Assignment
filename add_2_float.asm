# PROGRAM add_2_float
# This program will only dealt with normal single precision floating point number (IEEE 754) - no subnormal or inf or NaN
# Rounding is performed with the truncate method - all intermediate and final result will discard all fractional
# part outside of the 24-bit range
# If exponent fall outside the range 1-254 during operation, a warning is printed and the program end

# EQV
###################################################################
.eqv	EXP_LEN				8
.eqv	FRAC_LEN			24	# the format store only 23, the last one is implied 1 (for normal number)
.eqv	LEAD_0_INTERMEDIATE	8	# number of leading 0 when fractional part is stored in a register
.eqv	TEMP_REG_0			$t8	# for use within macro
.eqv	TEMP_REG_1			$t9	# for use within macro

# MACRO
###################################################################
# bit within range [high, low] (inclusive) will be extracted from reg
# bit index start from 0, with least significant bit indexed 0
# result is stored into result_reg at least significant digit
.macro M_EXTRACT_BIT_FROM(%reg, %high, %low, %result_reg)
	move	%result_reg, %reg
	li		TEMP_REG_0, %high
	addi	TEMP_REG_0, TEMP_REG_0, 1
	li		TEMP_REG_1, 32
	sub		TEMP_REG_0, TEMP_REG_1, TEMP_REG_0
	sllv	%result_reg, %result_reg, TEMP_REG_0
	addi	TEMP_REG_0, TEMP_REG_0, %low
	srlv	%result_reg, %result_reg, TEMP_REG_0
.end_macro

# extract the exponent from float wihtin reg
# result (8 bit at least significant digit) is stored into result_reg
.macro M_GET_EXPONENT_BIASED(%reg, %result_reg)
	M_EXTRACT_BIT_FROM(%reg, 30, 23, %result_reg)
.end_macro

# extract the fractional part from float within reg
# the fractional part extract will be 23 bit long - with 24th bit implied to be 1
# this implied 1 will be add in the extraction result
# result (24 bit at least significant bit) is stored into result_reg
.macro M_GET_FRACTIONAL_WITH_IMPLIED_1(%reg, %result_reg)
	M_EXTRACT_BIT_FROM(%reg, 22, 0, %result_reg)
	li		TEMP_REG_0, 0x00800000 # 24th bit set to 1
	or		%result_reg, %result_reg, TEMP_REG_0
.end_macro

# extract the sign part from float within reg
# result (1 bit at least significant bit) is stored into result_reg
.macro M_GET_SIGN(%reg, %result_reg)
	M_EXTRACT_BIT_FROM(%reg, 31, 31, %result_reg)
.end_macro

# shift the intermediate representaiton of a float to the left a specified amount of bit
# float is store as exponent in exp_reg and fractional part in frac_reg
# register provided are change in-place
.macro M_NORMALIZING_SHIFT_RIGHT(%exp_reg, %frac_reg, %amount_reg)
	add		%exp_reg, %exp_reg, %amount_reg
	srav	%frac_reg, %frac_reg, %amount_reg
.end_macro

# shift the intermediate representaiton of a float to the right a specified amount of bit
# float is store as exponent in exp_reg and fractional part in frac_reg
# register provided are change in-place
.macro M_NORMALIZING_SHIFT_LEFT(%exp_reg, %frac_reg, %amount_reg)
	sub		%exp_reg, %exp_reg, %amount_reg
	sllv	%frac_reg, %frac_reg, %amount_reg
.end_macro

# Compare the exponents of the two float numbers, both with intermediate representation
# shift the smaller number to the right until its
# exponent would match the larger exponent
.macro M_COMPARE_AND_SHIFT_BY_EXP(%exp_reg0, %frac_reg0, %exp_reg1, %frac_reg1)
	beq		%exp_reg0, %exp_reg1, both_exp_equal
	bltu	%exp_reg0, %exp_reg1, exp0_smaller_than_exp1
	j		exp1_smaller_than_exp0
	
	exp0_smaller_than_exp1:
	sub		TEMP_REG_0, %exp_reg1, %exp_reg0
	M_NORMALIZING_SHIFT_RIGHT(%exp_reg0, %frac_reg0, TEMP_REG_0)
	j		both_exp_equal
	
	exp1_smaller_than_exp0:
	sub		TEMP_REG_0, %exp_reg0, %exp_reg1
	M_NORMALIZING_SHIFT_RIGHT(%exp_reg1, %frac_reg1, TEMP_REG_0)
	#j		both_exp_equal
	
	both_exp_equal:
.end_macro

# Change the fractional part (24 bit) to is corresponding 2 complement
# if sign_reg stores 1 - chnage, 0 - no change
# result is stored in result_reg
.macro M_CHANGE_FRAC_TO_2_COMPLEMENT(%frac_reg, %sign_reg, %result_reg)
	move	%result_reg, %frac_reg
	beqz	%sign_reg, no_change
	subu	%result_reg, $0, %result_reg
	no_change:
.end_macro

# Add fractional part with respect to its sign
# result sign and fractional part is stored in result_frac_reg and result_sign_reg
.macro M_ADD_FRAC_WITH_SIGN(%frac_reg0, %sign_reg0, %frac_reg1, %sign_reg1, %result_frac_reg, %result_sign_reg)
	M_CHANGE_FRAC_TO_2_COMPLEMENT(%frac_reg0, %sign_reg0, TEMP_REG_0)
	M_CHANGE_FRAC_TO_2_COMPLEMENT(%frac_reg1, %sign_reg1, TEMP_REG_1)
	addu	%result_frac_reg, TEMP_REG_0, TEMP_REG_1
	li		%result_sign_reg, 0
	debug:
	ble		$0, %result_frac_reg, result_positive
	# if result is negative, change result to its 2-complement and set sign to 1
	li		%result_sign_reg, 1
	M_CHANGE_FRAC_TO_2_COMPLEMENT(%result_frac_reg, %result_sign_reg, %result_frac_reg)
	
	result_positive:
.end_macro

# check if exponent has over or under flow
# in either case, print message and jump to end of program
.macro M_CHECK_EXP_UNDER_OVER_FLOW(%exp_reg)
	li		TEMP_REG_0, 0xFF	# 255
	bge		%exp_reg, TEMP_REG_0, overflow
	ble		%exp_reg, $0, underflow
	j		normal
	
	overflow:
	underflow:
		la	$a0, error_message
		li	$v0, 4
		syscall
		j 	end_of_main_code
	
	normal:
.end_macro

# Add normalize the fractional part
# Such that the fractional part have only 24 bit (with the 24th bit being a 1)
# If that is not possible (require more than 24 shift), then the result must be 0
# The exponent can overflow (== 255) - which result in NaN, or underflow (== 0) - which create subnormal
# provided exponent and fractional part is change in place
.macro M_NORMALIZE(%exp_reg, %frac_reg)
	beq		%frac_reg, $0, need_no_normalization	# since fractional part is already 0, result must be 0
	clz		TEMP_REG_0, %frac_reg
	li		TEMP_REG_1, LEAD_0_INTERMEDIATE
	beq		TEMP_REG_0, TEMP_REG_1, need_no_normalization
	blt		TEMP_REG_0, TEMP_REG_1, too_big_need_shift_right
	
	too_small_need_shift_left:
	sub		TEMP_REG_0, TEMP_REG_0, TEMP_REG_1
	M_NORMALIZING_SHIFT_LEFT(%exp_reg, %frac_reg, TEMP_REG_0)
	M_CHECK_EXP_UNDER_OVER_FLOW(%exp_reg)
	j 		need_no_normalization
	
	too_big_need_shift_right:
	sub		TEMP_REG_0, TEMP_REG_1, TEMP_REG_0
	M_NORMALIZING_SHIFT_RIGHT(%exp_reg, %frac_reg, TEMP_REG_0)
	M_CHECK_EXP_UNDER_OVER_FLOW(%exp_reg)
	
	need_no_normalization:
.end_macro

# Combine all the part into a conforming IEEE754 single floating point representation
# result is written to result_reg
.macro M_GET_SINGLE_FLOAT_IEEE754(%exp_reg, %frac_reg, %sign_reg, %result_reg)
	and		%result_reg, $0, $0
	bne		%frac_reg, $0, frac_not_zero
	# frac is zero, create the result that reflect that
	# result exp will be 0, result frac will be zero, sign will be kept from intermediate representation
	j		add_sign_only

	frac_not_zero:
	# add exponent
	move	TEMP_REG_0, %exp_reg
	sll		TEMP_REG_0, TEMP_REG_0, 23
	or		%result_reg, %result_reg, TEMP_REG_0
	# add fractional part
	move	TEMP_REG_0, %frac_reg
	li	 	TEMP_REG_1, 0x7FFFFF
	and		TEMP_REG_0, TEMP_REG_0, TEMP_REG_1		# take only the first 23 bit of frac
	or		%result_reg, %result_reg, TEMP_REG_0
	
	add_sign_only:
	# add sign
	move	TEMP_REG_0, %sign_reg 
	sll		TEMP_REG_0, TEMP_REG_0, 31
	or		%result_reg, %result_reg, TEMP_REG_0
.end_macro

# DATA SEGMENT
###################################################################
.data
# VARIABLES
file_name:
	.asciiz "./FLOAT2.BIN"
	
input_buffer:
	.align 2 # aligned by word so it is separate from file_name in memory viewer
	.space 8
	
error_message: 
	.asciiz "Underflow or overflow of exponent detected when adding\n"

# CODE SEGMENT
###################################################################
.text

j		start_of_main_code

# function
# read file for 2 float, store into input_buffer
# after this we can consider input_buffer as array of 2 float
read_2_float_from_file:
	# open file
	li		$v0, 13
	la		$a0, file_name
	li		$a1, 0
	li		$a2, 0
	syscall

	# read 8 byte from byte
	move	$a0, $v0
	li		$v0, 14
	la		$a1, input_buffer
	li		$a2, 8
	syscall
	
	jr		$ra

# load content of input_buffer (2 float) into reg $v0, $v1
load_2_float_to_reg:
	la		$a0, input_buffer
	lw		$v0, 0($a1)
	lw 		$v1, 4($a1)
	
	jr		$ra
	
# print new line
print_new_line:
	li		$a0, '\n'
	li		$v0, 11
	syscall
	
	jr 		$ra

# print the content of reg (interpreted as a float)
# input read from $a0
print_float_from_reg:
	mtc1	$a0, $f12
	li		$v0, 2
	syscall
	
	jr 		$ra

start_of_main_code:
# read and move 2 float to $t0 and $t1
jal		read_2_float_from_file
jal		load_2_float_to_reg
move	$t0, $v0
move	$a0, $v0
jal 	print_float_from_reg
jal		print_new_line
move	$t1, $v1
move	$a0, $v1
jal 	print_float_from_reg
jal		print_new_line

# extract part within each float
# float 1 - exp($t2), frac($t3), sign($t4)
# float 2 - exp($t5), frac($t6), sign($t7)
M_GET_EXPONENT_BIASED($t0, $t2)
M_GET_FRACTIONAL_WITH_IMPLIED_1($t0, $t3)
M_GET_SIGN($t0, $t4)
M_GET_EXPONENT_BIASED($t1, $t5)
M_GET_FRACTIONAL_WITH_IMPLIED_1($t1, $t6)
M_GET_SIGN($t1, $t7)

# compare and normalized both intermediate representation
# meaning that shift the smaller float until it has equal exponent value to the other one
M_COMPARE_AND_SHIFT_BY_EXP($t2, $t3, $t5, $t6)

# by now both float's exponent ($t3 and $t6) must be equal
# add fractional part (with respect to their sign)
# result will be stored back to registers contaning float 1 ($t3 and $t4)
M_ADD_FRAC_WITH_SIGN($t3, $t4, $t6, $t7, $t3, $t4)

# now the result float is in the reg that used to contain float 1
# shift the fractional part of the result such that the fractional part is exactly 24 bit (with the 24th bit be 1)
# or if that is not possible, the result must be zero
M_NORMALIZE($t2, $t3)

# now compose the single floating point format from intermediate represenation
# and print out the result
M_GET_SINGLE_FLOAT_IEEE754($t2, $t3, $t4, $a0)
jal		print_float_from_reg
end_of_main_code:










