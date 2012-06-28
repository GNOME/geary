/* Copyright 2012 Yorba Foundation
*
* This software is licensed under the GNU Lesser General Public License
* (version 2.1 or later).  See the COPYING file in this distribution. 
*/

class GMime.FilterFlowed : GMime.Filter {
    public FilterFlowed() {
    }
    
    public override GMime.Filter copy() {
        return new FilterFlowed();
    }
    
    public override void filter(char[] inbuf, size_t prespace, out unowned char[] outbuf, out size_t outprespace) {
        StringBuilder inbuf_string = new StringBuilder();
        inbuf_string.append_len((string)inbuf, inbuf.length);
        string[] lines = inbuf_string.str.split("\r\n");
        int cur_quote_level = 0;
        bool was_flowed = false;
        bool first_line = true;
        StringBuilder builder = new StringBuilder();
        foreach(string line in lines) {
            int quote_level = 0;
            while(line[quote_level] == '>')
                quote_level++;
            if(first_line) {
                builder.append(line);
            } else if (quote_level == cur_quote_level && was_flowed) {
                builder.append(line[quote_level:line.length-1]);
            } else {
                builder.append("\r\n");
                builder.append(line);
            }
            was_flowed = line[line.length - 1] == ' ' && line != "-- ";
            cur_quote_level = quote_level;
            first_line = false;
        }
        
        // use length + 1 for terminating \0 if inbuf was null-terminated
        if (inbuf[inbuf.length - 1] == 0) {
            set_size(builder.len + 1, false);
            Memory.copy(this.outbuf, builder.str.data, builder.len + 1);
        } else {
            set_size(builder.len, false);
            Memory.copy(this.outbuf, builder.str.data, builder.len);
        }

        
        outbuf = this.outbuf;
        outprespace = this.outpre;
    }
    
    public override void complete(char[] inbuf, size_t prespace, out unowned char[] outbuf, out size_t outprespace) {
        if(inbuf != null && inbuf.length != 0) {
            this.filter (inbuf, prespace, out outbuf, out outprespace);
        } else {
            outbuf = this.outbuf;
            outprespace = this.outpre;
        }
    }
    
    public override void reset() {
    }
}
