/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A response code and additional information that optionally accompanies a server response.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 */

public class Geary.Imap.ResponseCode : Geary.Imap.ListParameter {
    public ResponseCode(ListParameter parent, Parameter? initial = null) {
        base (parent, initial);
    }
    
    public ResponseCodeType get_code_type() throws ImapError {
        return ResponseCodeType.from_parameter(get_as_string(0));
    }
    
    public override string to_string() {
        return "[%s]".printf(stringize_list());
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_ascii('[');
        yield serialize_list(ser);
        ser.push_ascii(']');
    }
}

