package uint128

import (
	"math"
	"testing"
)

func TestNew(t *testing.T) {
	tests := []struct {
		name     string
		hi, lo   uint64
		expected Uint128
	}{
		{"Zero", 0, 0, Uint128{0, 0}},
		{"One", 0, 1, Uint128{0, 1}},
		{"Max uint64", 0, ^uint64(0), Uint128{0, ^uint64(0)}},
		{"High bits set", 1, 0, Uint128{1, 0}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := New(tt.hi, tt.lo)
			if result != tt.expected {
				t.Errorf("New(%d, %d) = %v; want %v", tt.hi, tt.lo, result, tt.expected)
			}
		})
	}
}

func TestIsZero(t *testing.T) {
	tests := []struct {
		name     string
		u        Uint128
		expected bool
	}{
		{"Zero", Uint128{0, 0}, true},
		{"One", Uint128{0, 1}, false},
		{"High bits set", Uint128{1, 0}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.IsZero()
			if result != tt.expected {
				t.Errorf("%v.IsZero() = %v; want %v", tt.u, result, tt.expected)
			}
		})
	}
}

func TestAdd(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected Uint128
	}{
		{"Zero + Zero", Uint128{0, 0}, Uint128{0, 0}, Uint128{0, 0}},
		{"One + One", Uint128{0, 1}, Uint128{0, 1}, Uint128{0, 2}},
		{"Max uint64 + One", Uint128{0, ^uint64(0)}, Uint128{0, 1}, Uint128{1, 0}},
		// {"Overflow", Uint128{^uint64(0), ^uint64(0)}, Uint128{0, 1}, Uint128{0, 0}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Add(tt.v)
			if result != tt.expected {
				t.Errorf("%v.Add(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

func TestSub(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected Uint128
	}{
		{"Zero - Zero", Uint128{0, 0}, Uint128{0, 0}, Uint128{0, 0}},
		{"One - One", Uint128{0, 1}, Uint128{0, 1}, Uint128{0, 0}},
		// TODO: handle underflow
		// {"Underflow", Uint128{0, 0}, Uint128{0, 1}, Uint128{^uint64(0), ^uint64(0)}},
		{"High bits", Uint128{1, 0}, Uint128{0, 1}, Uint128{0, ^uint64(0)}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Sub(tt.v)
			if result != tt.expected {
				t.Errorf("%v.Sub(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

func TestAnd(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected Uint128
	}{
		{"All bits", Uint128{^uint64(0), ^uint64(0)}, Uint128{^uint64(0), ^uint64(0)}, Uint128{^uint64(0), ^uint64(0)}},
		{"No bits", Uint128{^uint64(0), ^uint64(0)}, Uint128{0, 0}, Uint128{0, 0}},
		{"Mixed bits", Uint128{0xF0F0, 0xF0F0}, Uint128{0xFF00, 0xFF00}, Uint128{0xF000, 0xF000}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.And(tt.v)
			if result != tt.expected {
				t.Errorf("%v.And(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

func TestOr(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected Uint128
	}{
		{"All bits", Uint128{^uint64(0), ^uint64(0)}, Uint128{0, 0}, Uint128{^uint64(0), ^uint64(0)}},
		{"No bits", Uint128{0, 0}, Uint128{0, 0}, Uint128{0, 0}},
		{"Mixed bits", Uint128{0xF0F0, 0xF0F0}, Uint128{0x0F0F, 0x0F0F}, Uint128{0xFFFF, 0xFFFF}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Or(tt.v)
			if result != tt.expected {
				t.Errorf("%v.Or(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

func TestLsh(t *testing.T) {
	tests := []struct {
		name     string
		u        Uint128
		n        uint
		expected Uint128
	}{
		{"No shift", Uint128{0x1, 0x1}, 0, Uint128{0x1, 0x1}},
		{"Shift 1", Uint128{0x1, 0x1}, 1, Uint128{0x2, 0x2}},
		{"Shift 63", Uint128{0x1, 0x1}, 63, Uint128{0x8000000000000000, 0x8000000000000000}},
		{"Shift 64", Uint128{0x1, 0x1}, 64, Uint128{0x1, 0x0}},
		{"Shift 65", Uint128{0x1, 0x1}, 65, Uint128{0x2, 0x0}},
		{"Shift 128", Uint128{0x1, 0x1}, 128, Uint128{0x0, 0x0}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Lsh(tt.n)
			if result != tt.expected {
				t.Errorf("%v.Lsh(%d) = %v; want %v", tt.u, tt.n, result, tt.expected)
			}
		})
	}
}

func TestRsh(t *testing.T) {
	tests := []struct {
		name     string
		u        Uint128
		n        uint
		expected Uint128
	}{
		{"No shift", Uint128{0x1, 0x1}, 0, Uint128{0x1, 0x1}},
		{"Shift 1", Uint128{0x2, 0x2}, 1, Uint128{0x1, 0x1}},
		{"Shift 63", Uint128{0x8000000000000000, 0x8000000000000000}, 63, Uint128{0x1, 0x1}},
		{"Shift 64", Uint128{0x1, 0x0}, 64, Uint128{0x0, 0x1}},
		{"Shift 65", Uint128{0x2, 0x0}, 65, Uint128{0x0, 0x1}},
		{"Shift 128", Uint128{0x1, 0x1}, 128, Uint128{0x0, 0x0}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Rsh(tt.n)
			if result != tt.expected {
				t.Errorf("%v.Rsh(%d) = %v; want %v", tt.u, tt.n, result, tt.expected)
			}
		})
	}
}

func TestMul(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected Uint128
	}{
		{"Zero * Zero", New(0, 0), New(0, 0), New(0, 0)},
		{"One * One", New(0, 1), New(0, 1), New(0, 1)},
		{"Max uint64 * 2", New(0, ^uint64(0)), New(0, 2), New(1, ^uint64(0)-1)},
		{"(2^64) * 2", New(1, 0), New(0, 2), New(2, 0)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Mul(tt.v)
			if result != tt.expected {
				t.Errorf("%v.Mul(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

// func TestUint128Div(t *testing.T) {
// 	tests := []struct {
// 		name     string
// 		dividend Uint128
// 		divisor  Uint128
// 		expected string
// 	}{
// 		{
// 			name:     "1 / 1",
// 			dividend: New(1, 0),
// 			divisor:  New(1, 0),
// 			expected: New(1, 0).String(),
// 		},
// 		{
// 			name:     "Big number / Small number",
// 			dividend: New(0, 1),
// 			divisor:  New(2, 0),
// 			expected: "9223372036854775808",
// 		},
// 	}

// 	for _, tt := range tests {
// 		t.Run(tt.name, func(t *testing.T) {
// 			result := tt.dividend.Div(tt.divisor)
// 			if result.String() != tt.expected {
// 				t.Errorf("Div() = %v, want %v", result.String(), tt.expected)
// 			}
// 		})
// 	}
// }

// func TestUint128DivDiscrepancy(t *testing.T) {
// 	// Test case 1: Replicating main function behavior
// 	t.Run("MainFunctionBehavior", func(t *testing.T) {
// 		max := New(^uint64(0), ^uint64(0)) // 2^128 - 1
// 		maxDiv2 := max.Div(New(0, 2))      // 2*2^64
// 		result := maxDiv2.String()
// 		expected := "9223372036854775807"

// 		if result != expected {
// 			t.Errorf("Main function behavior: got %s, want %s", result, expected)
// 		}
// 	})

// 	// Test case 2: Direct Div method call
// 	t.Run("DirectDivMethodCall", func(t *testing.T) {
// 		dividend := New(0, 1) // 2^64
// 		divisor := New(2, 0)  // 2
// 		result := dividend.Div(divisor).String()
// 		expected := "9223372036854775808"

// 		if result != expected {
// 			t.Errorf("Direct Div method call: got %s, want %s", result, expected)
// 		}
// 	})
// }

func TestUint128Div64(t *testing.T) {
	tests := []struct {
		name     string
		dividend Uint128
		divisor  uint64
		expected Uint128
	}{
		{
			name:     "Max / 2 (using Div64)",
			dividend: New(^uint64(0), ^uint64(0)),
			divisor:  2,
			expected: New(9223372036854775807, 18446744073709551615),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.dividend.Div64(tt.divisor)
			if result != tt.expected {
				t.Errorf("Div64() = %v, want %v", result, tt.expected)
			}
		})
	}
}

func TestCmp(t *testing.T) {
	tests := []struct {
		name     string
		u, v     Uint128
		expected int
	}{
		{"Equal", New(1, 1), New(1, 1), 0},
		{"Less than", New(1, 0), New(1, 1), -1},
		{"Greater than", New(2, 0), New(1, ^uint64(0)), 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.Cmp(tt.v)
			if result != tt.expected {
				t.Errorf("%v.Cmp(%v) = %v; want %v", tt.u, tt.v, result, tt.expected)
			}
		})
	}
}

func TestString(t *testing.T) {
	tests := []struct {
		name     string
		u        Uint128
		expected string
	}{
		{"Zero", New(0, 0), "0"},
		{"One", New(0, 1), "1"},
		{"Max uint64", New(0, ^uint64(0)), "18446744073709551615"},
		{"2^64", New(1, 0), "18446744073709551616"},
		{"Max uint128", New(^uint64(0), ^uint64(0)), "340282366920938463463374607431768211455"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.u.String()
			if result != tt.expected {
				t.Errorf("%v.String() = %v; want %v", tt.u, result, tt.expected)
			}
		})
	}
}

func TestLeadingZeros(t *testing.T) {
	tcs := []struct {
		l     Uint128
		r     Uint128
		zeros int
	}{
		{
			l:     New(0x00, 0xf000000000000000),
			r:     New(0x00, 0x8000000000000000),
			zeros: 1,
		},
		{
			l:     New(0x00, 0xf000000000000000),
			r:     New(0x00, 0xc000000000000000),
			zeros: 2,
		},
		{
			l:     New(0x00, 0xf000000000000000),
			r:     New(0x00, 0xe000000000000000),
			zeros: 3,
		},
		{
			l:     New(0x00, 0xffff000000000000),
			r:     New(0x00, 0xff00000000000000),
			zeros: 8,
		},
		{
			l:     New(0x00, 0x000000000000ffff),
			r:     New(0x00, 0x000000000000ff00),
			zeros: 56,
		},
		{
			l:     New(0xf000000000000000, 0x01),
			r:     New(0x4000000000000000, 0x00),
			zeros: 63,
		},
		{
			l:     New(0xf000000000000000, 0x00),
			r:     New(0x4000000000000000, 0x00),
			zeros: 64,
		},
		{
			l:     New(0xf000000000000000, 0x00),
			r:     New(0x8000000000000000, 0x00),
			zeros: 65,
		},
		{
			l:     New(0x00, 0x00),
			r:     New(0x00, 0x00),
			zeros: 128,
		},
		{
			l:     New(0x01, 0x00),
			r:     New(0x00, 0x00),
			zeros: 127,
		},
	}

	for _, tc := range tcs {
		zeros := tc.l.Xor(tc.r).LeadingZeros()
		if zeros != tc.zeros {
			t.Errorf("mismatch (expected: %d, got: %d)", tc.zeros, zeros)
		}
	}
}

func TestFromString(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    Uint128
		wantErr bool
	}{
		{"Zero", "0", Zero, false},
		{"One", "1", New(0, 1), false},
		{"Max uint64", "18446744073709551615", New(0, 18446744073709551615), false},
		// {"Min uint128 overflow", "18446744073709551616", New(1, 0), false},
		// {"Large number", "340282366920938463463374607431768211455", Max, false},
		// TODO
		// {"Overflow", "340282366920938463463374607431768211456", Zero, true},
		{"Negative", "-1", Zero, true},
		{"Invalid character", "12a34", Zero, true},
		{"Empty string", "", Zero, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := FromString(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("FromString() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("FromString() = %v, want %v", got, tt.want)
			}
		})
	}
}
