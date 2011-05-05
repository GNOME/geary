/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ResponseCode : Geary.Imap.ListParameter {
    public ResponseCode(ListParameter parent, Parameter? initial = null) {
        base (parent, initial);
    }
    
    public override string to_string() {
        return "[%s]".printf(stringize_list());
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_ascii('[');
        serialize_list(ser);
        ser.push_ascii(']');
    }
}

