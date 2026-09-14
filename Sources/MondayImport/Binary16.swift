import Foundation

extension Float {
    init(binary16 bits: UInt16) {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32((bits >> 10) & 0x1f)
        var fraction = UInt32(bits & 0x03ff)
        let value: UInt32

        if exponent == 0 {
            if fraction == 0 {
                value = sign
            } else {
                var normalizedExponent = 113
                while fraction & 0x0400 == 0 {
                    fraction <<= 1
                    normalizedExponent -= 1
                }
                value = sign | UInt32(normalizedExponent << 23) | (fraction & 0x03ff) << 13
            }
        } else if exponent == 0x1f {
            value = sign | 0x7f80_0000 | fraction << 13
        } else {
            value = sign | (exponent + 112) << 23 | fraction << 13
        }
        self = Float(bitPattern: value)
    }
}
