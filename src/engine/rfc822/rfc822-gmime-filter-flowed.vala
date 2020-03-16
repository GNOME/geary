/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael James Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Filter to correctly handle flowed text as described in RFC 3676.
 *
 * This class assumes that CRLF sequences have been replaced with a
 * single LF character.
 *
 * The character `Geary.RFC822.Utils.QUOTE_MARKER` will be output as the
 * quote character instead of `>` if the `to_html` constructor
 * argument is set to `true`.
 */
private class Geary.RFC822.FilterFlowed : GMime.Filter {

    private char quote_marker;
    private bool delsp;

    // Invariant: True iff the last character seen was a space.
    private bool saw_space = false;

    // Invariant: True iff we are either at the beginning of a line,
    // or all characters seen so far have been '>'s.
    private bool in_prefix = false;

    // Invariant: The number of '>'s seen after parsing the prefix.
    private uint quote_level = 0;

    // Invariant: The number of consecutive '-'s seen.
    private uint sig_level = 0;

    public FilterFlowed(bool to_html, bool delsp) {
        this.quote_marker = to_html ? Geary.RFC822.Utils.QUOTE_MARKER : '>';
        this.delsp = delsp;
    }

    public override void reset() {
        this.saw_space = false;
        this.in_prefix = true;
        this.quote_level = 0;
        this.sig_level = 0;
    }

    public override GMime.Filter copy() {
        FilterFlowed new_filter = new FilterFlowed(quote_marker == Geary.RFC822.Utils.QUOTE_MARKER, delsp);

        new_filter.saw_space = this.saw_space;
        new_filter.in_prefix = this.in_prefix;
        new_filter.quote_level = this.quote_level;
        new_filter.sig_level = this.sig_level;

        return new_filter;
    }

    public override void filter([CCode (array_length_type = "gsize")] uint8[] inbuf, size_t prespace, [CCode (array_length_type = "gsize")] out unowned uint8[] processed_buffer,
        out size_t outprespace) {

        // Worst-case scenario: We are about to leave the prefix,
        // resulting in an extra (quote_level + 2) characters being
        // written.
        set_size(inbuf.length + this.quote_level + 2, false);

        uint out_index = 0;
        for (uint i = 0; i < inbuf.length; i++) {
            uint8 c = inbuf[i];

            if (this.in_prefix) {
                if (c == '>') {
                    // Don't write the prefix right away, because we
                    // don't want to write it if the last line was
                    // flowed.
                    this.quote_level++;
                    continue;
                }

                // Found something other than a '>', so we are out of
                // the prefix and need to write out an appropriate
                // number of quote chars.

                for (uint j = 0; j < this.quote_level; j++)
                    outbuf[out_index++] = this.quote_marker;

                this.in_prefix = false;

                // A single space following the prefix is space stuffed
                if (c == ' ')
                    continue;
            }

            switch (c) {
                case ' ':
                    if (this.saw_space) {
                        // Two spaces in a row, so output the last
                        // space and clear the signature test
                        outbuf[out_index++] = ' ';
                        this.sig_level = 0;
                    }
                    // We can't write the space yet, since it might be
                    // removed if DelSp is true. Don't clear the
                    // signature test since we might be in one.
                    this.saw_space = true;
                break;

                case '\n':
                    if (this.saw_space && this.sig_level != 2) {
                        // We have a SP+LF sequence that wasn't part
                        // of a signature, so treat as a soft break
                        // and flow line on to the next one.
                        if (!this.delsp)
                            outbuf[out_index++] = ' ';
                    } else {
                        // Else this is a hard break.
                        if (this.saw_space) {
                            outbuf[out_index++] = ' ';
                        }
                        outbuf[out_index++] = c;
                    }

                    // We are done with this line, so we are in the
                    // prefix of the next line (and have not yet seen
                    // any '>' characters in the next line).
                    this.in_prefix = true;
                    this.quote_level = 0;
                    this.saw_space = false;
                    this.sig_level = 0;
                break;

                default:
                    // We cannot be in a ' \n' sequence, so just write
                    // the character.
                    if (this.saw_space)
                        outbuf[out_index++] = ' ';
                    outbuf[out_index++] = c;
                    this.sig_level = (c == '-') ? this.sig_level + 1 : 0;
                    this.saw_space = false;
                break;
            }
        }

        // Slicing the buffer is important, because the buffer is not null-terminated,
        processed_buffer = outbuf[0:out_index];
        outprespace = this.outpre;
    }

    public override void complete([CCode (array_length_type = "gsize")] uint8[] inbuf, size_t prespace, [CCode (array_length_type = "gsize")] out unowned uint8[] processed_buffer,
        out size_t outprespace) {
        filter(inbuf, prespace, out processed_buffer, out outprespace);
    }
}
