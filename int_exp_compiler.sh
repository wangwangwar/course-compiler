#!/bin/bash

source_file=$1
rkt_suff=rkt
asm_suff=s
exe_suff=out
target_asm_file=${source_file%$rkt_suff}$asm_suff
target_exe_file=${source_file%$rkt_suff}$exe_suff

racket int_exp_compiler.rkt $source_file
gcc -g runtime.o $target_asm_file -o $target_exe_file

$target_exe_file