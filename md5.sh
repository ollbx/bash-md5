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
	0xd76aa478 0xe8c7b756 0x242070db 0xc1bdceee
	0xf57c0faf 0x4787c62a 0xa8304613 0xfd469501
	0x698098d8 0x8b44f7af 0xffff5bb1 0x895cd7be
	0x6b901122 0xfd987193 0xa679438e 0x49b40821
	0xf61e2562 0xc040b340 0x265e5a51 0xe9b6c7aa
	0xd62f105d 0x02441453 0xd8a1e681 0xe7d3fbc8
	0x21e1cde6 0xc33707d6 0xf4d50d87 0x455a14ed
	0xa9e3e905 0xfcefa3f8 0x676f02d9 0x8d2a4c8a
	0xfffa3942 0x8771f681 0x6d9d6122 0xfde5380c
	0xa4beea44 0x4bdecfa9 0xf6bb4b60 0xbebfbc70
	0x289b7ec6 0xeaa127fa 0xd4ef3085 0x04881d05
	0xd9d4d039 0xe6db99e5 0x1fa27cf8 0xc4ac5665
	0xf4292244 0x432aff97 0xab9423a7 0xfc93a039
	0x655b59c3 0x8f0ccc92 0xffeff47d 0x85845dd1
	0x6fa87e4f 0xfe2ce6e0 0xa3014314 0x4e0811a1
	0xf7537e82 0xbd3af235 0x2ad7d2bb 0xeb86d391
)

# Used to mask the lower 32 bit of an integer.
readonly MASK=0xffffffff

# ------------------------------------------------------------------------------
# Global state
# ------------------------------------------------------------------------------

eof=0 # 1 once EOF has been reached.
len=0 # length of read input (without padding).

state=(0x67452301 0xefcdab89 0x98badcfe 0x10325476)

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
				E=$(( C ^ (B | ND) ))
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
		printf '%02x' $((  state[i] & 0x000000ff ))
		printf '%02x' $(( (state[i] & 0x0000ff00) >> 8 ))
		printf '%02x' $(( (state[i] & 0x00ff0000) >> 16 ))
		printf '%02x' $(( (state[i] & 0xff000000) >> 24 ))
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
		# it will return an empty string. Conveniently `printf "%d" "'"`
		# will then print 0.
		printf '%d' "'${chr}"
		((len++))
	else
		# Output 0x80 at EOF and 0x00 afterwards.
		echo $(( (1 - eof) * 0x80 ))
		eof=1
	fi

	# TODO: read data in chunks, keeping the same interface.
	#
	# - 1: if no chunk is available, read one and reset index to 0.
	# - 2: if index  < #chunk: extract byte and increase index.
	# - 3: if index >= #chunk: clear the chunk and goto 1.
	# - figure out the padding / EOF stuff to go along with this.
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
