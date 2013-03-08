/* Copyright 2012 Yorba Foundation
*
* This software is licensed under the GNU Lesser General Public License
* (version 2.1 or later).  See the COPYING file in this distribution. 
*/

// Filter to correctly handle flowed text as described in RFC 2646.
class GMime.FilterFlowed : GMime.Filter {
    private char quote_marker;
    private bool delsp;
    
    // Invariant: True iff the last character seen was a space OR the penultimate character seen
    // was a space and the last character seen was a \r.
    private bool saw_space;
    
    // Invariant: True iff the last character seen was a \r.
    private bool saw_cr;
    
    // Invariant: True iff the last \r\n encountered was preceded by a space.
    private bool last_line_was_flowed;
    
    // Invariant: True iff we are in the prefix for the first line.
    private bool in_first_prefix;
    
    // Invariant: True iff we are either at the beginning of a line, or all characters seen so far
    // have been '>'s.
    private bool in_prefix;
    
    // Invariant: The quote depth of the last complete line seen, or 0 if we have not yet seen a
    // complete line.
    private uint last_quote_level;
    
    // Invariant: The number of '>'s seen so far if we are parsing the prefix, or 0 if we are not
    // parsing the prefix.
    private uint current_quote_level;
    
    public FilterFlowed(bool to_html, bool delsp) {
        quote_marker = to_html ? Geary.RFC822.Utils.QUOTE_MARKER : '>';
        this.delsp = delsp;
        reset();
    }
    
    public override void reset() {
        saw_space = false;
        saw_cr = false;
        last_line_was_flowed = false;
        in_first_prefix = true;
        in_prefix = true;
        last_quote_level = 0;
        current_quote_level = 0;
    }
    
    public override GMime.Filter copy() {
        FilterFlowed new_filter = new FilterFlowed(quote_marker == '\x7f', delsp);
        
        new_filter.saw_space = saw_space;
        new_filter.saw_cr = saw_cr;
        new_filter.last_line_was_flowed = last_line_was_flowed;
        new_filter.in_first_prefix = in_first_prefix;
        new_filter.in_prefix = in_prefix;
        new_filter.last_quote_level = last_quote_level;
        new_filter.current_quote_level = current_quote_level;
        
        return new_filter;
    }
    
    public override void filter(char[] inbuf, size_t prespace, out unowned char[] processed_buffer,
        out size_t outprespace) {
        
        // Worst-case scenario: We are about to leave the prefix, resulting in an extra
        // (current_quote_level + 2) characters being written.
        set_size(inbuf.length + current_quote_level + 2, false);
        
        uint out_index = 0;
        for (uint i = 0; i < inbuf.length; i++) {
            char c = inbuf[i];
            
            if (in_prefix) {
                if (c == '>') {
                    // Don't write the prefix right away, because we don't want to write it if the
                    // last line was flowed.
                    current_quote_level++;
                    continue;
                }
                
                if (in_first_prefix) {
                    for (uint j = 0; j < current_quote_level; j++)
                        outbuf[out_index++] = quote_marker;
                } else if (!last_line_was_flowed || current_quote_level != last_quote_level ||
                    (out_index > 3 && Geary.RFC822.Utils.comp_char_arr_slice(outbuf, out_index - 4, "\n-- "))) {
                    // We encountered a non-flowed line-break, so insert a CRLF.
                    outbuf[out_index++] = '\r';
                    outbuf[out_index++] = '\n';
                    
                    // We haven't been writing the quote prefix as we've scanned it, so we need to
                    // write it now.
                    for (uint j = 0; j < current_quote_level; j++)
                        outbuf[out_index++] = quote_marker;
                } else if (delsp) {
                    // Line was flowed, so get rid of trailing space
                    out_index -= 1;
                }
                
                // We saw a character other than '>', so we're done scanning the prefix.
                in_first_prefix = false;
                in_prefix = false;
                last_quote_level = current_quote_level;
                current_quote_level = 0;
                
                // A single space following the prefix is space stuffed
                if (c == ' ')
                    continue;
            }
            
            switch (c) {
                case ' ':
                    saw_space = true;
                    saw_cr = false;
                    
                    // We'll write the space right away, since it often will be needed.  The 
                    // exception is if it's a space marking a flowed line and DelSp is true, but
                    // we deal with that by deleting this space before later.
                    outbuf[out_index++] = c;
                break;
                
                case '\r':
                    if (saw_cr) {
                        // The last 3 charcters were ' \r\r', so we can't have ' \r\n'.
                        saw_space = false;
                        // We didn't write the preceding CR when we saw it, so we write it now.
                        outbuf[out_index++] = '\r';
                    }
                    
                    saw_cr = true;
                    // We can't write the CR until we know it isn't part of a flowed line.
                break;
                
                case '\n':
                    if (saw_cr) {
                        // If the last 3 charcters were ' \r\n', the line was flowed.
                        last_line_was_flowed = saw_space;
                        
                        // We are done with this line, so we are in the prefix of the next line
                        // (and have not yet seen any '>' charcacters in the next line).
                        in_prefix = true;
                        current_quote_level = 0;
                    } else {
                        // The LF wasn't part of a CRLF, so just write it.
                        outbuf[out_index++] = c;
                    }
                    
                    saw_space = false;
                    saw_cr = false;
                break;
                
                default:
                    // We cannot be in a ' \r\n' sequence, so just write the character.
                    saw_space = false;
                    saw_cr = false;
                    outbuf[out_index++] = c;
                break;
            }
        }
        
        // Slicing the buffer is important, because the buffer is not null-terminated,
        processed_buffer = outbuf[0:out_index];
        outprespace = this.outpre;
    }
    
    public override void complete(char[] inbuf, size_t prespace, out unowned char[] processed_buffer,
        out size_t outprespace) {
        filter(inbuf, prespace, out processed_buffer, out outprespace);
    }
}
