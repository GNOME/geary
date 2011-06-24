/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.FolderProperties : Geary.FolderProperties {
    public UID? uid_validity { get; set; }
    public MailboxAttributes attrs { get; private set; }
    public Trillian supports_children { get; private set; }
    public Trillian has_children { get; private set; }
    public Trillian is_openable { get; private set; }
    
    public FolderProperties(UID? uid_validity, MailboxAttributes attrs) {
        this.uid_validity = uid_validity;
        this.attrs = attrs;
        
        supports_children = Trillian.from_boolean(!attrs.contains(MailboxAttribute.NO_INFERIORS));
        // \HasNoChildren is an optional attribute and lack of presence doesn't indiciate anything
        supports_children = attrs.contains(MailboxAttribute.HAS_NO_CHILDREN) ? Trillian.TRUE
            : Trillian.UNKNOWN;
        is_openable = Trillian.from_boolean(!attrs.contains(MailboxAttribute.NO_SELECT));
    }
}

