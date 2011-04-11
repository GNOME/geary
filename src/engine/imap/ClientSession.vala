/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSession {
    private int tag_counter = 0;
    private char tag_prefix = 'a';
    
    // Generates a unique tag for the IMAP session in the form of "<a-z><000-999>".
    public string generate_tag_value() {
        // watch for odometer rollover
        if (++tag_counter >= 1000) {
            tag_counter = 0;
            if (tag_prefix == 'z')
                tag_prefix = 'a';
            else
                tag_prefix++;
        }
        
        return "%c%03d".printf(tag_prefix, tag_counter);
    }
}

