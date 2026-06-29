#!/usr/bin/env bash

if [[ $1 = '-h' || $1 = '--help' ]]; then
	echo "Usage: cat data | $0"
	echo
	echo "Reads data from stdin and prints out the MD5 digest."
	exit 1
fi

readonly S=(
	7 12 17 22 7 12 17 22 7 12 17 22 7 12 17 22
	5  9 14 20 5  9 14 20 5  9 14 20 5  9 14 20
	4 11 16 23 4 11 16 23 4 11 16 23 4 11 16 23
	6 10 15 21 6 10 15 21 6 10 15 21 6 10 15 21
)

readonly K=(
	16#d76aa478 16#e8c7b756 16#242070db 16#c1bdceee
	16#f57c0faf 16#4787c62a 16#a8304613 16#fd469501
	16#698098d8 16#8b44f7af 16#ffff5bb1 16#895cd7be
	16#6b901122 16#fd987193 16#a679438e 16#49b40821
	16#f61e2562 16#c040b340 16#265e5a51 16#e9b6c7aa
	16#d62f105d 16#02441453 16#d8a1e681 16#e7d3fbc8
	16#21e1cde6 16#c33707d6 16#f4d50d87 16#455a14ed
	16#a9e3e905 16#fcefa3f8 16#676f02d9 16#8d2a4c8a
	16#fffa3942 16#8771f681 16#6d9d6122 16#fde5380c
	16#a4beea44 16#4bdecfa9 16#f6bb4b60 16#bebfbc70
	16#289b7ec6 16#eaa127fa 16#d4ef3085 16#04881d05
	16#d9d4d039 16#e6db99e5 16#1fa27cf8 16#c4ac5665
	16#f4292244 16#432aff97 16#ab9423a7 16#fc93a039
	16#655b59c3 16#8f0ccc92 16#ffeff47d 16#85845dd1
	16#6fa87e4f 16#fe2ce6e0 16#a3014314 16#4e0811a1
	16#f7537e82 16#bd3af235 16#2ad7d2bb 16#eb86d391
)

# Used to mask the lower 32 bit of an integer.
readonly MASK=16#ffffffff

# ------------------------------------------------------------------------------
# Global state
# ------------------------------------------------------------------------------

eof=0 # 1 once EOF has been reached.
len=0 # length of read input (without padding).

state=(16#67452301 16#efcdab89 16#98badcfe 16#10325476)

# ------------------------------------------------------------------------------
# Usage: rotate_left [NUM] [N]
#
# Rotates `NUM` left by `N`.
# ------------------------------------------------------------------------------

rotate_left() {
	# Note: only `lhs` can overflow into 64 bit.
	local lhs=$((($1 << $2) & MASK))
	local rhs=$(($1 >> (32 - $2)))
	echo $((lhs | rhs))
}

# ------------------------------------------------------------------------------
# Usage: md5_step [WORDS]
#
# Processes a full block of input data given by `WORDS`. `WORDS` is expected to
# be exactly 16 32-bit integers. Updates the global `state`.
# ------------------------------------------------------------------------------

md5_step() {
	local words=("$@")

	if [[ ${#words[@]} -ne 16 ]]; then
		echo Input is not a full block. 1>&2
		exit 1
	fi

	local A=${state[0]}
	local B=${state[1]}
	local C=${state[2]}
	local D=${state[3]}
	local E=0
	local j=0

	for i in {0..63}; do
		case $((i / 16)) in
			0)
				local NB=$((~B & MASK))
				E=$(( (B & C) | (NB & D) ))
				j=$i
				;;
			1)
				local ND=$((~D & MASK))
				E=$(( (B & D) | (C & ND) ))
				j=$(( ((i * 5) + 1) % 16 ))
				;;
			2)
				E=$(( B ^ C ^ D ))
				j=$(( ((i * 3) + 5) % 16 ))
				;;
			3)
				local ND=$((~D & MASK))
				E=$((C ^ (B | ND)))
				j=$(( (i * 7) % 16 ))
				;;
		esac

		local sum=$(( (A + E + K[i] + ${words[j]}) & MASK ))
		local rot=${ rotate_left ${sum} ${S[i]}; }
		local tmp=$D
		D=$C
		C=$B
		B=$(( (B + rot) & MASK ))
		A=$tmp
	done

	state[0]=$(( ((state[0] + A) & MASK) ))
	state[1]=$(( ((state[1] + B) & MASK) ))
	state[2]=$(( ((state[2] + C) & MASK) ))
	state[3]=$(( ((state[3] + D) & MASK) ))
}

# ------------------------------------------------------------------------------
# Usage: md5_finish [WORDS]
#
# Processes the final block of input data given by `WORDS`. `WORDS` is expected
# to be exactly 16 32-bit integers. Updates the global `state`.
#
# Note: if the input is too short for the final block, padding needs to be added
# to produce the 16 `WORDS`.
# ------------------------------------------------------------------------------

md5_finish() {
	local words=("$@")

	# How much of the current block is actually used by data?
	local offset=$(( len % 64 ))

	if [[ ${offset} -ge 56 ]]; then
		# Not enough space. We need another block to write the size.
		md5_step "${words[@]}"
		words=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
	fi

	# These two words should be zero now.
	if [[ ${words[14]} -ne 0 || ${words[15]} -ne 0 ]]; then
		echo Padding words are not empty. 1>&2
		exit 1
	fi

	local bits=$((len * 8))
	words[14]=$(( bits & MASK ))
	words[15]=$(( bits >> 32 ))
	md5_step "${words[@]}"
}

# ------------------------------------------------------------------------------
# Usage: md5_digest
#
# Outputs the digest for the current `state` in hexadecimal.
# ------------------------------------------------------------------------------

md5_digest() {
	for i in {0..3}; do
		printf '%02x' $((  state[i] & 16#000000ff ))
		printf '%02x' $(( (state[i] & 16#0000ff00) >> 8 ))
		printf '%02x' $(( (state[i] & 16#00ff0000) >> 16 ))
		printf '%02x' $(( (state[i] & 16#ff000000) >> 24 ))
	done
	echo
}

# ------------------------------------------------------------------------------
# Usage: into_word [A] [B] [C] [D]
#
# Combines four bytes given by `A` to `D` and combines them into a little-endian
# 32-bit word.
# ------------------------------------------------------------------------------

into_word() {
	echo $(($1 + ($2 << 8) + ($3 << 16) + ($4 << 24)))
}

# ------------------------------------------------------------------------------
# Usage: read_byte
#
# Reads the next byte from stdin and returns it as an integer. On EOF, the
# global variable `eof` is set to 1. When called after EOF, the function will
# start returning padding bytes (0x80 followed by 0x00).
#
# Reading a (non-padded) byte will also increase the global `len` by one.
# ------------------------------------------------------------------------------

read_byte() {
	# Note `LC_ALL=C` prevents read from trying to make sense of UTF-8
	# sequences etc.
	if LC_ALL=C IFS= read -rd '' -n 1 chr; then
		# Echo the byte value. Note: when `read` encounters a null byte
		# it will returns an empty string. `printf "%d" "'"` will then
		# return 0.
		printf '%d' "'${chr}"
		((len++))
	else
		# Output 0x80 at EOF and 0x00 afterwards.
		echo $(( (1 - eof) * 16#80 ))
		eof=1
	fi
}

# ------------------------------------------------------------------------------
# Usage: read_byte
#
# Reads input from stdin and calculates the MD5 hash along the way. Prints out
# the digest, when EOF is encountered.
# ------------------------------------------------------------------------------

read_input() {
	local bytes=()
	local words=()

	while true; do
		# Read byte by byte. `read_byte` will automatically pad once
		# EOF has been reached.
		bytes+=(${ read_byte; })

		# Convert every 4 bytes into a 32-bit word.
		if [[ ${#bytes[@]} -ge 4 ]]; then
			words+=(${ into_word "${bytes[@]}"; })
			bytes=()
		fi

		# Finish a block when we reach 16 words.
		if [[ ${#words[@]} -ge 16 ]]; then
			# Do the final processing once we are at EOF.
			if [[ ${eof} -eq 1 ]]; then
				md5_finish "${words[@]}"
				md5_digest
				break
			fi

			# Otherwise just process the block and reset `words`.
			md5_step "${words[@]}"
			words=()
		fi
	done
}

read_input
