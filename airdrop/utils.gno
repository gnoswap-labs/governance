package airdrop

import (
	"gno.land/p/demo/ufmt"
)

const (
	MaxUint64 = 1<<64 - 1
	uintSize  = 32 << (^uint(0) >> 63)
)

func lower(c byte) byte {
	return c | ('x' - 'X')
}

// TODO: Remove parseUint after gno supports strconv.ParseUint
func parseUint(s string, base int, bitSize int) (uint64, error) {
	const fnParseUint = "ParseUint"

	if s == "" {
		return 0, ufmt.Errorf("%s: parsing \"\": invalid syntax", fnParseUint)
	}

	base0 := base == 0

	s0 := s
	switch {
	case 2 <= base && base <= 36:
		// valid base; nothing to do

	case base == 0:
		// Look for octal, hex prefix.
		base = 10
		if s[0] == '0' {
			switch {
			case len(s) >= 3 && lower(s[1]) == 'b':
				base = 2
				s = s[2:]
			case len(s) >= 3 && lower(s[1]) == 'o':
				base = 8
				s = s[2:]
			case len(s) >= 3 && lower(s[1]) == 'x':
				base = 16
				s = s[2:]
			default:
				base = 8
				s = s[1:]
			}
		}

	default:
		return 0, ufmt.Errorf("%s: invalid base %d", fnParseUint, base)
	}

	if bitSize == 0 {
		bitSize = uintSize
	} else if bitSize < 0 || bitSize > 64 {
		return 0, ufmt.Errorf("%s: invalid bit size %d", fnParseUint, bitSize)
	}

	// Cutoff is the smallest number such that cutoff*base > maxUint64.
	// Use compile-time constants for common cases.
	var cutoff uint64
	switch base {
	case 10:
		cutoff = MaxUint64/10 + 1
	case 16:
		cutoff = MaxUint64/16 + 1
	default:
		cutoff = MaxUint64/uint64(base) + 1
	}

	maxVal := uint64(1)<<uint(bitSize) - 1

	underscores := false
	var n uint64
	for _, c := range []byte(s) {
		var d byte
		switch {
		case c == '_' && base0:
			underscores = true
			continue
		case '0' <= c && c <= '9':
			d = c - '0'
		case 'a' <= lower(c) && lower(c) <= 'z':
			d = lower(c) - 'a' + 10
		default:
			return 0, ufmt.Errorf("%s: invalid character", fnParseUint)
		}

		if d >= byte(base) {
			return 0, ufmt.Errorf("%s: invalid character", fnParseUint)
		}

		if n >= cutoff {
			// n*base overflows
			return maxVal, ufmt.Errorf("%s: value out of range", fnParseUint)
		}
		n *= uint64(base)

		n1 := n + uint64(d)
		if n1 < n || n1 > maxVal {
			// n+d overflows
			return maxVal, ufmt.Errorf("%s: value out of range", fnParseUint)
		}
		n = n1
	}

	if underscores && !underscoreOK(s0) {
		return 0, ufmt.Errorf("%s: invalid underscore", fnParseUint)
	}

	return n, nil
}

func underscoreOK(s string) bool {
	// saw tracks the last character (class) we saw:
	// ^ for beginning of number,
	// 0 for a digit or base prefix,
	// _ for an underscore,
	// ! for none of the above.
	saw := '^'
	i := 0

	// Optional sign.
	if len(s) >= 1 && (s[0] == '-' || s[0] == '+') {
		s = s[1:]
	}

	// Optional base prefix.
	hex := false
	if len(s) >= 2 && s[0] == '0' && (lower(s[1]) == 'b' || lower(s[1]) == 'o' || lower(s[1]) == 'x') {
		i = 2
		saw = '0' // base prefix counts as a digit for "underscore as digit separator"
		hex = lower(s[1]) == 'x'
	}

	// Number proper.
	for ; i < len(s); i++ {
		// Digits are always okay.
		if '0' <= s[i] && s[i] <= '9' || hex && 'a' <= lower(s[i]) && lower(s[i]) <= 'f' {
			saw = '0'
			continue
		}
		// Underscore must follow digit.
		if s[i] == '_' {
			if saw != '0' {
				return false
			}
			saw = '_'
			continue
		}
		// Underscore must also be followed by digit.
		if saw == '_' {
			return false
		}
		// Saw non-digit, non-underscore.
		saw = '!'
	}
	return saw != '_'
}

func b2i(b bool) uint8 {
	if b {
		return 1
	}
	return 0
}

func b2s(b bool) string {
	if b {
		return "true"
	}
	return "false"
}
