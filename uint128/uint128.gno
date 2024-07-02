package uint128

import (
	"errors"
	"math"
	"math/bits"
)

var (
	Zero Uint128
	Max  = New(math.MaxUint64, math.MaxUint64)
)

// Uint128 represents a 128-bit unsigned integer
type Uint128 struct {
	Hi uint64 // Most significant bits
	Lo uint64 // Least significant bits
}

// New creates a new Uint128 from two uint64 values
func New(hi, lo uint64) Uint128 {
	return Uint128{Hi: hi, Lo: lo}
}

// From64 converts v to a Uint128 value.
func From64(v uint64) Uint128 {
	return New(v, 0)
}

// IsZero returns true if the Uint128 is zero
func (u Uint128) IsZero() bool {
	return u.Lo == 0 && u.Hi == 0
}

// Add adds two Uint128 numbers
func (u Uint128) Add(v Uint128) Uint128 {
	lo, carry := bits.Add64(u.Lo, v.Lo, 0)
	hi, _ := bits.Add64(u.Hi, v.Hi, carry)
	return Uint128{Lo: lo, Hi: hi}
}

// Add64 returns u+v.
func (u Uint128) Add64(v uint64) Uint128 {
	lo, carry := bits.Add64(u.Lo, v, 0)
	hi, carry := bits.Add64(u.Hi, 0, carry)
	if carry != 0 {
		panic("overflow")
	}
	return Uint128{lo, hi}
}

// Sub subtracts v from u
func (u Uint128) Sub(v Uint128) Uint128 {
	lo, borrow := bits.Sub64(u.Lo, v.Lo, 0)
	hi, borrow := bits.Sub64(u.Hi, v.Hi, borrow)
	if borrow != 0 {
		panic("underflow")
	}
	return Uint128{Lo: lo, Hi: hi}
}

// And performs bitwise AND operation
func (u Uint128) And(v Uint128) Uint128 {
	return Uint128{Lo: u.Lo & v.Lo, Hi: u.Hi & v.Hi}
}

// Or performs bitwise OR operation
func (u Uint128) Or(v Uint128) Uint128 {
	return Uint128{Lo: u.Lo | v.Lo, Hi: u.Hi | v.Hi}
}

// Lsh performs left shift
func (u Uint128) Lsh(n uint) Uint128 {
	if n >= 128 {
		return Uint128{Lo: 0, Hi: 0}
	}
	if n >= 64 {
		return Uint128{Lo: 0, Hi: u.Lo << (n - 64)}
	}
	return Uint128{
		Lo: u.Lo << n,
		Hi: u.Hi<<n | u.Lo>>(64-n),
	}
}

// Rsh performs right shift
func (u Uint128) Rsh(n uint) Uint128 {
	if n > 64 {
		return Uint128{Lo: u.Hi >> (n - 64), Hi: 0}
	}
	if n == 64 {
		return Uint128{Lo: u.Hi, Hi: 0}
	}
	if n == 0 {
		return u
	}
	return Uint128{
		Lo: u.Lo>>n | u.Hi<<(64-n),
		Hi: u.Hi >> n,
	}
}

// Mul multiplies two Uint128 numbers
func (u Uint128) Mul(v Uint128) Uint128 {
	hi, lo := bits.Mul64(u.Lo, v.Lo)
	hi += u.Hi*v.Lo + u.Lo*v.Hi
	return Uint128{Hi: hi, Lo: lo}
}

// Mul64 returns u*v, panicking on overflow.
func (u Uint128) Mul64(v uint64) Uint128 {
	hi, lo := bits.Mul64(u.Lo, v)
	p0, p1 := bits.Mul64(u.Hi, v)
	hi, c0 := bits.Add64(hi, p1, 0)
	if p0 != 0 || c0 != 0 {
		panic("overflow")
	}
	return Uint128{lo, hi}
}

// Div divides u by v and returns the quotient
// Panics if v is zero
func (u Uint128) Div(v Uint128) Uint128 {
	q, _ := u.QuoRem(v)
	return q
}

// Div64 returns u/v.
func (u Uint128) Div64(v uint64) Uint128 {
	q, _ := u.QuoRem64(v)
	return q
}

// QuoRem returns q = u/v and r = u%v.
func (u Uint128) QuoRem(v Uint128) (q, r Uint128) {
	if v.Hi == 0 {
		var r64 uint64
		q, r64 = u.QuoRem64(v.Lo)
		r = From64(r64)
	} else {
		// generate a "trial quotient," guaranteed to be within 1 of the actual
		// quotient, then adjust.
		n := uint(bits.LeadingZeros64(v.Hi))
		v1 := v.Lsh(n)
		u1 := u.Rsh(1)
		tq, _ := bits.Div64(u1.Hi, u1.Lo, v1.Hi)
		tq >>= 63 - n
		if tq != 0 {
			tq--
		}
		q = From64(tq)
		// calculate remainder using trial quotient, then adjust if remainder is
		// greater than divisor
		r = u.Sub(v.Mul64(tq))
		if r.Cmp(v) >= 0 {
			q = q.Add64(1)
			r = r.Sub(v)
		}
	}
	return
}

// QuoRem64 returns q = u/v and r = u%v.
func (u Uint128) QuoRem64(v uint64) (q Uint128, r uint64) {
	if u.Hi < v {
		q.Lo, r = bits.Div64(u.Hi, u.Lo, v)
	} else {
		q.Hi, r = bits.Div64(0, u.Hi, v)
		q.Lo, r = bits.Div64(r, u.Lo, v)
	}
	return
}

// Bit returns the value of the bit at position i
func (u Uint128) Bit(i uint) uint {
	if i < 64 {
		return uint((u.Lo >> i) & 1)
	}
	return uint((u.Hi >> (i - 64)) & 1)
}

// divByUint64 divides u by a uint64 value
func (u Uint128) divByUint64(v uint64) Uint128 {
	if v == 0 {
		panic("division by zero")
	}
	if u.Hi < v {
		q, _ := bits.Div64(u.Hi, u.Lo, v)
		return Uint128{Hi: 0, Lo: q}
	}
	hi, r := bits.Div64(0, u.Hi, v)
	lo, _ := bits.Div64(r, u.Lo, v)
	return Uint128{Hi: hi, Lo: lo}
}

// Cmp compares u with v and returns:
//
//	-1 if u  < v
//	 0 if u == v
//	+1 if u >  v
func (u Uint128) Cmp(v Uint128) int {
	if u == v {
		return 0
	} else if u.Hi < v.Hi || (u.Hi == v.Hi && u.Lo < v.Lo) {
		return -1
	} else {
		return 1
	}
}

// Lt returns true if u < v
func (u Uint128) Lt(v Uint128) bool {
	return u.Cmp(v) < 0
}

// Lte returns true if u <= v
func (u Uint128) Lte(v Uint128) bool {
	return u.Cmp(v) <= 0
}

// Gt returns true if u > v
func (u Uint128) Gt(v Uint128) bool {
	return u.Cmp(v) > 0
}

// Gte returns true if u >= v
func (u Uint128) Gte(v Uint128) bool {
	return u.Cmp(v) >= 0
}

func (u Uint128) Xor(v Uint128) Uint128 {
	return Uint128{u.Lo ^ v.Lo, u.Hi ^ v.Hi}
}

// LeadingZeros returns the number of leading zero bits in u
func (u Uint128) LeadingZeros() int {
	if u.Hi == 0 {
		return 64 + bits.LeadingZeros64(u.Lo)
	}
	return bits.LeadingZeros64(u.Hi)
}

// String returns a decimal string representation of u
func (u Uint128) String() string {
	if u.IsZero() {
		return "0"
	}
	buf := []byte("0000000000000000000000000000000000000000") // log10(2^128) < 40
	for i := len(buf); ; i -= 19 {
		q, r := u.QuoRem64(1e19) // largest power of 10 that fits in a uint64
		var n int
		for ; r != 0; r /= 10 {
			n++
			buf[i-n] += byte(r % 10)
		}
		if q.IsZero() {
			return string(buf[i-n:])
		}
		u = q
	}
}

func FromString(s string) (Uint128, error) {
	if s == "" {
		return Zero, errors.New("empty string")
	}
	var result Uint128
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return Zero, errors.New("invalid character in input")
		}

		digit := uint64(ch - '0')

		// Check for overflow before multiplication
		if result.Hi > 0 || (result.Lo > math.MaxUint64/10) ||
			(result.Lo == math.MaxUint64/10 && digit > math.MaxUint64%10) {
			return Zero, errors.New("number too large for Uint128")
		}

		// Multiply result by 10
		result.Lo *= 10

		// Check for overflow before addition
		if math.MaxUint64-result.Lo < digit {
			return Zero, errors.New("number too large for Uint128")
		}

		// Add the new digit
		result.Lo += digit
	}

	return result, nil
}
