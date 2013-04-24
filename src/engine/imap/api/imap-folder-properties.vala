/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.FolderProperties : Geary.FolderProperties {
    /**
     * -1 if the Folder was not opened via SELECT or EXAMINE.
     */
    public int select_examine_messages { get; private set; }
    /**
     * -1 if the FolderProperties were not obtained via a STATUS command
     */
    public int status_messages { get; private set; }
    public int unseen { get; private set; }
    public int recent { get; private set; }
    public UIDValidity? uid_validity { get; private set; }
    public UID? uid_next { get; private set; }
    public MailboxAttributes attrs { get; private set; }
    
    // Note that unseen from SELECT/EXAMINE is the *position* of the first unseen message,
    // not the total unseen count, so it should not be passed in here, but rather the unseen
    // count from a STATUS command
    public FolderProperties(int messages, int recent, int unseen, UIDValidity? uid_validity,
        UID? uid_next, MailboxAttributes attrs) {
        base (messages, unseen, Trillian.UNKNOWN, Trillian.UNKNOWN, Trillian.UNKNOWN);
        
        select_examine_messages = messages;
        status_messages = -1;
        this.recent = recent;
        this.unseen = unseen;
        this.uid_validity = uid_validity;
        this.uid_next = uid_next;
        this.attrs = attrs;
        
        init_flags();
    }
    
    public FolderProperties.status(StatusData status, MailboxAttributes attrs) {
        base (status.messages, status.unseen, Trillian.UNKNOWN, Trillian.UNKNOWN, Trillian.UNKNOWN);
        
        select_examine_messages = -1;
        status_messages = status.messages;
        recent = status.recent;
        unseen = status.unseen;
        uid_validity = status.uid_validity;
        uid_next = status.uid_next;
        this.attrs = attrs;
        
        init_flags();
    }
    
    /**
     * Use with FolderProperties of the *same folder* seen at different times (i.e. after SELECTing
     * versus data stored locally).  Only compares fields that suggest the contents of the folder
     * have changed.
     *
     * Note that this is *not* concerned with message flags changing.
     */
    public Trillian have_contents_changed(Geary.Imap.FolderProperties other) {
        // UIDNEXT changes indicate messages have been added, but not if they've been removed
        if (uid_next != null && other.uid_next != null && !uid_next.equals(other.uid_next))
            return Trillian.TRUE;
        
        // Gmail includes Chat messages in STATUS results but not in SELECT/EXAMINE
        // results, so message count comparison has to be from the same origin ... use SELECT/EXAMINE
        // first, as it's more authoritative in many ways
        //
        // TODO: If this continues to work, it might be worthwhile to change the result of this
        // method to boolean
        if (select_examine_messages >= 0 && other.select_examine_messages >= 0
            && select_examine_messages != other.select_examine_messages) {
            return Trillian.TRUE;
        }
        
        if (status_messages >= 0 && other.status_messages >= 0 && status_messages != other.status_messages) {
            return Trillian.TRUE;
        }
        
        return Trillian.FALSE;
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
    
    public void set_status_message_count(int messages, bool force) {
        if (messages < 0)
            return;
        
        status_messages = messages;
        
        // select/examine more authoritative than status, unless the caller knows otherwise
        if (force || (select_examine_messages < 0))
            email_total = messages;
    }
    
    public void set_select_examine_message_count(int messages) {
        if (messages < 0)
            return;
        
        select_examine_messages = messages;
        
        // select/examine more authoritative than status
        email_total = messages;
    }
}

