/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Tag : StringParameter {
    public Tag.generated(ClientSession session) {
        base (session.generate_tag_value());
    }
    
    public Tag(string value) {
        base (value);
    }
    
    public bool is_untagged() {
        return value == "*";
    }
}

