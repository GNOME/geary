/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.FolderProperties {
    // messages can be updated a variety of ways, so it's available as a public set
    public int messages { get; set; }
    public int recent { get; private set; }
    public int unseen { get; private set; }
    public UIDValidity? uid_validity { get; private set; }
    public UID? uid_next { get; private set; }
    public MailboxAttributes attrs { get; private set; }
    public Trillian supports_children { get; private set; }
    public Trillian has_children { get; private set; }
    public Trillian is_openable { get; private set; }
    
    public FolderProperties(int messages, int recent, int unseen, UIDValidity? uid_validity,
        UID? uid_next, MailboxAttributes attrs) {
        this.messages = messages;
        this.recent = recent;
        this.unseen = unseen;
        this.uid_validity = uid_validity;
        this.uid_next = uid_next;
        this.attrs = attrs;
        
        init_flags();
    }
    
    public FolderProperties.status(StatusResults status, MailboxAttributes attrs) {
        messages = status.messages;
        recent = status.recent;
        unseen = status.unseen;
        uid_validity = status.uid_validity;
        uid_next = status.uid_next;
        this.attrs = attrs;
        
        init_flags();
    }
    
    private void init_flags() {
        supports_children = Trillian.from_boolean(!attrs.contains(MailboxAttribute.NO_INFERIORS));
        // \HasNoChildren & \HasChildren are optional attributes (could check for CHILDREN extension,
        // but unnecessary here)
        if (attrs.contains(MailboxAttribute.HAS_NO_CHILDREN))
            has_children = Trillian.FALSE;
        else if (attrs.contains(MailboxAttribute.HAS_CHILDREN))
            has_children = Trillian.TRUE;
        else
            has_children = Trillian.UNKNOWN;
        is_openable = Trillian.from_boolean(!attrs.contains(MailboxAttribute.NO_SELECT));
    }
}

