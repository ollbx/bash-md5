#!/usr/bin/env bash

file=$(mktemp)

# Test various lengths. Make sure to include the block boundary at 64 bytes.
for i in {0..191}; do
	openssl rand ${i} >"${file}"
	ref=${ cat "${file}" | openssl md5 --binary | xxd -p; }
	res=${ cat "${file}" | ./md5.sh; }

	if [[ "${ref}" = "${res}" ]]; then
		echo "${i}: OK (${ref})"
	else
		echo
		echo "${i}: mismatch"
		echo "expected: ${ref}"
		echo "found:    ${res}"
		echo
		cat "${file}" | xxd;
		echo
	fi

done

# Test one large block.
dd if=/dev/urandom bs=4K count=1 >"${file}" 2>/dev/null
ref=${ cat "${file}" | openssl md5 --binary | xxd -p; }
res=${ cat "${file}" | ./md5.sh; }

if [[ "${ref}" = "${res}" ]]; then
	echo "4096: OK (${ref})"
else
	echo
	echo "4096: mismatch"
	echo "expected: ${ref}"
	echo "found:    ${res}"
	echo
fi

rm "${file}"
