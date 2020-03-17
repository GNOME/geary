/* Copyright 2016 Software Freedom Conservancy Inc.
*
* This software is licensed under the GNU Lesser General Public License
* (version 2.1 or later).  See the COPYING file in this distribution.
*/

// Filter to mark quoted text in plain (non-flowed) text
private class Geary.RFC822.FilterPlain : GMime.Filter {
    // Invariant: True iff we are either at the beginning of a line, or all characters seen so far
    // have been quote markers.
    private bool in_prefix;

    public FilterPlain() {
        reset();
    }

    public override void reset() {
        in_prefix = true;
    }

    public override GMime.Filter copy() {
        FilterPlain new_filter = new FilterPlain();

        new_filter.in_prefix = in_prefix;

        return new_filter;
    }

    public override void filter([CCode (array_length_type = "gsize")] uint8[] inbuf, size_t prespace, [CCode (array_length_type = "gsize")] out unowned uint8[] processed_buffer,
        out size_t outprespace) {

        // This may not be strictly necessary.
        set_size(inbuf.length, false);

        uint out_index = 0;
        for (uint i = 0; i < inbuf.length; i++) {
            uint8 c = inbuf[i];

            if (in_prefix) {
                if (c == '>') {
                    outbuf[out_index++] = Geary.RFC822.Utils.QUOTE_MARKER;
                    continue;
                }

                // We saw a character other than '>', so we're done scanning the prefix.
                in_prefix = false;
            }

            if (c == '\n')
                in_prefix = true;
            outbuf[out_index++] = c;
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
