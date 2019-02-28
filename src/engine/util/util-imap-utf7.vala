/* Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright (c) 2008-2012 Dovecot authors
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.ImapUtf7 {

/* This file was modified from Dovecot's LGPLv2.1-licensed implementation in
 * dovecot-2.1.15/src/lib-imap/imap-utf7.c.
 */

/* These UTF16_* parts were modified from Dovecot's MIT-licensed Unicode
 * library header in dovecot-2.1.15/src/lib/unichar.h.  I don't believe it's a
 * substantial enough portion to warrant inclusion of the MIT license.
 */

/* Characters >= base require surrogates */
private const unichar UTF16_SURROGATE_BASE = 0x10000;

private const int UTF16_SURROGATE_SHIFT = 10;
private const unichar UTF16_SURROGATE_MASK = 0x03ff;
private const unichar UTF16_SURROGATE_HIGH_FIRST = 0xd800;
private const unichar UTF16_SURROGATE_HIGH_LAST = 0xdbff;
private const unichar UTF16_SURROGATE_HIGH_MAX = 0xdfff;
private const unichar UTF16_SURROGATE_LOW_FIRST = 0xdc00;
private const unichar UTF16_SURROGATE_LOW_LAST = 0xdfff;

private unichar UTF16_SURROGATE_HIGH(unichar chr) {
    return (UTF16_SURROGATE_HIGH_FIRST +
        (((chr) - UTF16_SURROGATE_BASE) >> UTF16_SURROGATE_SHIFT));
}
private unichar UTF16_SURROGATE_LOW(unichar chr) {
    return (UTF16_SURROGATE_LOW_FIRST +
        (((chr) - UTF16_SURROGATE_BASE) & UTF16_SURROGATE_MASK));
}

private const string imap_b64enc =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+,";

private const uint8 XX = 0xff;
private const uint8 imap_b64dec[256] = {
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,62, 63,XX,XX,XX,
    52,53,54,55, 56,57,58,59, 60,61,XX,XX, XX,XX,XX,XX,
    XX, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,
    15,16,17,18, 19,20,21,22, 23,24,25,XX, XX,XX,XX,XX,
    XX,26,27,28, 29,30,31,32, 33,34,35,36, 37,38,39,40,
    41,42,43,44, 45,46,47,48, 49,50,51,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
    XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX
};

private void mbase64_encode(StringBuilder dest, uint8[] input) {
    dest.append_c('&');
    int pos = 0;
    int len = input.length;
    while (len >= 3) {
        dest.append_c(imap_b64enc[input[pos + 0] >> 2]);
        dest.append_c(imap_b64enc[((input[pos + 0] & 3) << 4) |
                      (input[pos + 1] >> 4)]);
        dest.append_c(imap_b64enc[((input[pos + 1] & 0x0f) << 2) |
                      ((input[pos + 2] & 0xc0) >> 6)]);
        dest.append_c(imap_b64enc[input[pos + 2] & 0x3f]);
        pos += 3;
        len -= 3;
    }
    if (len > 0) {
        dest.append_c(imap_b64enc[input[pos + 0] >> 2]);
        if (len == 1)
            dest.append_c(imap_b64enc[(input[pos + 0] & 0x03) << 4]);
        else {
            dest.append_c(imap_b64enc[((input[pos + 0] & 0x03) << 4) |
                          (input[pos + 1] >> 4)]);
            dest.append_c(imap_b64enc[(input[pos + 1] & 0x0f) << 2]);
        }
    }
    dest.append_c('-');
}

private int first_encode_index(string str) {
    for (int p = 0; str[p] != '\0'; p++) {
        if (str[p] == '&' || (uint8) str[p] >= 0x80)
            return p;
    }
    return -1;
}

public string utf8_to_imap_utf7(string str) {
    int p = first_encode_index(str);
    if (p < 0) {
        /* no characters that need to be encoded */
        return str;
    }

    /* at least one encoded character */
    StringBuilder dest = new StringBuilder();
    dest.append_len(str, p);
    while (p < str.length) {
        if (str[p] == '&') {
            dest.append("&-");
            p++;
            continue;
        }
        if ((uint8) str[p] < 0x80) {
            dest.append_c(str[p]);
            p++;
            continue;
        }

        uint8[] utf16 = {};
        while ((uint8) str[p] >= 0x80) {
            int next_p = p;
            unichar chr;
            // TODO: validate this conversion, throw ConvertError?
            str.get_next_char(ref next_p, out chr);
            if (chr < UTF16_SURROGATE_BASE) {
                utf16 += (uint8) (chr >> 8);
                utf16 += (uint8) (chr & 0xff);
            } else {
                unichar u16 = UTF16_SURROGATE_HIGH(chr);
                utf16 += (uint8) (u16 >> 8);
                utf16 += (uint8) (u16 & 0xff);
                u16 = UTF16_SURROGATE_LOW(chr);
                utf16 += (uint8) (u16 >> 8);
                utf16 += (uint8) (u16 & 0xff);
            }
            p = next_p;
        }
        mbase64_encode(dest, utf16);
    }
    return dest.str;
}

private void utf16buf_to_utf8(StringBuilder dest, uint8[] output, ref int pos, int len) throws ConvertError {
    if (len % 2 != 0)
        throw new ConvertError.ILLEGAL_SEQUENCE("Odd number of bytes in UTF-16 data");

    uint16 high = (output[pos % 4] << 8) | output[(pos+1) % 4];
    if (high < UTF16_SURROGATE_HIGH_FIRST ||
        high > UTF16_SURROGATE_HIGH_MAX) {
        /* single byte */
        string? s = ((unichar) high).to_string();
        if (s == null)
            throw new ConvertError.ILLEGAL_SEQUENCE("Couldn't convert U+%04hx to UTF-8", high);
        dest.append(s);
        pos = (pos + 2) % 4;
        return;
    }

    if (high > UTF16_SURROGATE_HIGH_LAST)
        throw new ConvertError.ILLEGAL_SEQUENCE("UTF-16 data out of range");
    if (len != 4) {
        /* missing the second character */
        throw new ConvertError.ILLEGAL_SEQUENCE("Truncated UTF-16 data");
    }

    uint16 low = (output[(pos+2)%4] << 8) | output[(pos+3) % 4];
    if (low < UTF16_SURROGATE_LOW_FIRST || low > UTF16_SURROGATE_LOW_LAST)
        throw new ConvertError.ILLEGAL_SEQUENCE("Illegal UTF-16 surrogate");

    unichar chr = UTF16_SURROGATE_BASE +
        (((high & UTF16_SURROGATE_MASK) << UTF16_SURROGATE_SHIFT) |
         (low & UTF16_SURROGATE_MASK));
    string? s = chr.to_string();
    if (s == null)
        throw new ConvertError.ILLEGAL_SEQUENCE("Couldn't convert U+%04x to UTF-8", chr);
    dest.append(s);
}

private void mbase64_decode_to_utf8(StringBuilder dest, string str, ref int p) throws ConvertError {
    uint8 input[4], output[4];
    int outstart = 0, outpos = 0;

    while (str[p] != '-') {
        input[0] = imap_b64dec[(uint8) str[p + 0]];
        input[1] = imap_b64dec[(uint8) str[p + 1]];
        if (input[0] == 0xff || input[1] == 0xff)
            throw new ConvertError.ILLEGAL_SEQUENCE("Illegal character in IMAP base-64 encoded sequence");

        output[outpos % 4] = (input[0] << 2) | (input[1] >> 4);
        if (++outpos % 4 == outstart) {
            utf16buf_to_utf8(dest, output, ref outstart, 4);
        }

        input[2] = imap_b64dec[(uint8) str[p + 2]];
        if (input[2] == 0xff) {
            if (str[p + 2] != '-')
                throw new ConvertError.ILLEGAL_SEQUENCE("Illegal character in IMAP base-64 encoded sequence");

            p += 2;
            break;
        }

        output[outpos % 4] = (input[1] << 4) | (input[2] >> 2);
        if (++outpos % 4 == outstart) {
            utf16buf_to_utf8(dest, output, ref outstart, 4);
        }

        input[3] = imap_b64dec[(uint8) str[p + 3]];
        if (input[3] == 0xff) {
            if (str[p + 3] != '-')
                throw new ConvertError.ILLEGAL_SEQUENCE("Illegal character in IMAP base-64 encoded sequence");

            p += 3;
            break;
        }

        output[outpos % 4] = ((input[2] << 6) & 0xc0) | input[3];
        if (++outpos % 4 == outstart) {
            utf16buf_to_utf8(dest, output, ref outstart, 4);
        }

        p += 4;
    }
    if (outstart != outpos % 4) {
        utf16buf_to_utf8(dest, output, ref outstart, (4 + outpos - outstart) % 4);
    }

    /* found ending '-' */
    p++;
}

public string imap_utf7_to_utf8(string str) throws ConvertError {
    int p;
    for (p = 0; str[p] != '\0'; p++) {
        if (str[p] == '&' || (uint8) str[p] >= 0x80)
            break;
    }
    if (str[p] == '\0') {
        /* no IMAP-UTF-7 encoded characters */
        return str;
    }
    if ((uint8) str[p] >= 0x80) {
        /* 8bit characters - the input is broken */
        throw new ConvertError.ILLEGAL_SEQUENCE("IMAP UTF-7 input string contains 8-bit data");
    }

    /* at least one encoded character */
    StringBuilder dest = new StringBuilder();
    dest.append_len(str, p);
    while (str[p] != '\0') {
        if (str[p] == '&') {
            if (str[++p] == '-') {
                dest.append_c('&');
                p++;
            } else {
                mbase64_decode_to_utf8(dest, str, ref p);
                if (str[p + 0] == '&' && str[p + 1] != '-') {
                    /* &...-& */
                    throw new ConvertError.ILLEGAL_SEQUENCE("Illegal break in encoded text");
                }
            }
        } else {
            dest.append_c(str[p++]);
        }
    }
    return dest.str;
}

}
