/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.StatusResponse : ServerResponse {
    public Status status { get; private set; }
    
    public StatusResponse(Tag tag) {
        base (tag);
    }
    
    public StatusResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
        
        status = Status.from_parameter(get_as_string(1));
    }
    
    public string? get_text() {
        // build text from all StringParameters ... this will skip any ResponseCode or ListParameter
        // (or NilParameter, for that matter)
        StringBuilder builder = new StringBuilder();
        for (int index = 2; index < get_count(); index++) {
            StringParameter? strparam = get_if_string(index);
            if (strparam != null) {
                builder.append(strparam.value);
                if (index < (get_count() - 1))
                    builder.append_c(' ');
            }
        }
        
        return !String.is_empty(builder.str) ? builder.str : null;
    }
    
    public static bool is_status_response(RootParameters root) {
        try {
            Status.from_parameter(root.get_as_string(1));
            
            return true;
        } catch (ImapError err) {
            return false;
        }
    }
}

