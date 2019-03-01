/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Geary.Imap.FolderProperties represent the Geary API's notion of FolderProperties but
 * also hangs additional useful information available to IMAP-specific code (in the Engine,
 * that includes imap, imap-engine, and imap-db).
 *
 * One important concept here is that there are two IMAP commands that return this information:
 * STATUS (which is used by the background folder monitor to watch for specific events) and
 * SELECT/EXAMINE (which is used to "enter" or "cd" into a folder and perform operations on mail
 * within).
 *
 * Experience has shown that these commands are *not* guaranteed to return the same information,
 * even if no state has changed on the server.  This would seem to be a server bug, but one that
 * has to be worked around.
 *
 * In any event, the properties here are updated by the following logic:
 *
 * When a folder is first "seen" by Geary, it generates an Imap.FolderProperties object with all
 * the fields filled in except for status_messages or select_examine_messages, depending on which
 * command was used to discover it.  (In practice, the folder will be first recognized via STATUS,
 * but this isn't guaranteed.)
 *
 * When new STATUS information comes in, this object's status_messages, unseen, recent, and attrs
 * fields are updated.
 *
 * When a SELECT/EXAMINE occurs on this folder, this object's select_examine_messages,
 * recent, uid_validity, and uid_next are updated.
 *
 * Over time, this object accumulates information depending on what operation was last
 * performed on it.
 *
 * The base class' email_total is updated when either *_messages is updated; however, SELECT/EXAMINE
 * is considered more authoritative than STATUS.
 */

public class Geary.Imap.FolderProperties : Geary.FolderProperties {
    /**
     * -1 if the Folder was not opened via SELECT or EXAMINE.  Updated as EXISTS server data
     * arrives.
     */
    public int select_examine_messages { get; private set; }
    /**
     * -1 if the FolderProperties were not obtained or updated via a STATUS command
     */
    public int status_messages { get; private set; }
    /**
     * -1 if the FolderProperties were not obtained or updated via a STATUS command
     */
    public int unseen { get; private set; }
    public int recent { get; internal set; }
    public UIDValidity? uid_validity { get; internal set; }
    public UID? uid_next { get; internal set; }
    public MailboxAttributes attrs { get; internal set; }


    /**
     * Constructs properties for an IMAP folder that can be selected.
     */
    public FolderProperties.selectable(MailboxAttributes attrs,
                                       StatusData status,
                                       Capabilities capabilities) {
        this(
            attrs,
            status.messages,
            status.unseen,
            capabilities.supports_uidplus()
        );

        this.select_examine_messages = -1;
        this.status_messages = status.messages;
        this.recent = status.recent;
        this.unseen = status.unseen;
        this.uid_validity = status.uid_validity;
        this.uid_next = status.uid_next;
    }

    /**
     * Constructs properties for an IMAP folder that can not be selected.
     */
    public FolderProperties.not_selectable(MailboxAttributes attrs) {
        this(attrs, 0, 0, false);

        this.select_examine_messages = 0;
        this.status_messages = -1;
        this.recent = 0;
        this.unseen = -1;
        this.uid_validity = null;
        this.uid_next = null;
    }

    /**
     * Reconstitutes properties for an IMAP folder from the database
     */
    internal FolderProperties.from_imapdb(MailboxAttributes attrs,
                                          int email_total,
                                          int email_unread,
                                          UIDValidity? uid_validity,
                                          UID? uid_next) {
        this(attrs, email_total, email_unread, false);

        this.select_examine_messages = email_total;
        this.status_messages = -1;
        this.recent = 0;
        this.unseen = -1;
        this.uid_validity = uid_validity;
        this.uid_next = uid_next;
    }

    protected FolderProperties(MailboxAttributes attrs,
                               int email_total,
                               int email_unread,
                               bool supports_uid) {
        Trillian has_children = Trillian.UNKNOWN;
        if (attrs.contains(MailboxAttribute.HAS_NO_CHILDREN))
            has_children = Trillian.FALSE;
        else if (attrs.contains(MailboxAttribute.HAS_CHILDREN))
            has_children = Trillian.TRUE;

        Trillian supports_children = Trillian.UNKNOWN;
        // has_children implies supports_children
        if (has_children != Trillian.UNKNOWN) {
            supports_children = has_children;
        } else {
            // !supports_children implies !has_children
            supports_children = Trillian.from_boolean(!attrs.contains(MailboxAttribute.NO_INFERIORS));
            if (supports_children.is_impossible())
                has_children = Trillian.FALSE;
        }

        Trillian is_openable = Trillian.from_boolean(!attrs.is_no_select);

        base(email_total, email_unread,
             has_children, supports_children, is_openable,
             false, // not local
             false, // not virtual
             !supports_uid);

        this.attrs = attrs;
    }

    /**
     * Use with {@link FolderProperties} of the *same folder* seen at different times (i.e. after
     * SELECTing versus data stored locally).  Only compares fields that suggest the contents of
     * the folder have changed.
     *
     * Note that have_contents_changed does *not* discern if message flags have changed.
     */
    public bool have_contents_changed(Geary.Imap.FolderProperties other, string name) {
        // UIDNEXT changes indicate messages have been added, but not if they've been removed
        if (uid_next != null && other.uid_next != null && !uid_next.equal_to(other.uid_next)) {
            debug("%s FolderProperties changed: UIDNEXT=%s other.UIDNEXT=%s", name,
                uid_next.to_string(), other.uid_next.to_string());

            return true;
        }

        // UIDVALIDITY changes indicate the entire folder's contents have potentially altered and
        // the client needs to reset its local vector
        if (uid_validity != null && other.uid_validity != null && !uid_validity.equal_to(other.uid_validity)) {
            debug("%s FolderProperties changed: UIDVALIDITY=%s other.UIDVALIDITY=%s", name,
                uid_validity.to_string(), other.uid_validity.to_string());

            return true;
        }

        // Gmail includes Chat messages in STATUS results but not in SELECT/EXAMINE
        // results, so message count comparison has to be from the same origin ... use SELECT/EXAMINE
        // first, as it's more authoritative in many ways
        if (select_examine_messages >= 0 && other.select_examine_messages >= 0) {
            int diff = select_examine_messages - other.select_examine_messages;
            if (diff != 0) {
                debug("%s FolderProperties changed: SELECT/EXAMINE=%d other.SELECT/EXAMINE=%d diff=%d",
                    name, select_examine_messages, other.select_examine_messages, diff);

                return true;
            }
        }

        if (status_messages >= 0 && other.status_messages >= 0) {
            int diff = status_messages - other.status_messages;
            if (diff != 0) {
                debug("%s FolderProperties changed: STATUS=%d other.STATUS=%d diff=%d", name,
                    status_messages, other.status_messages, diff);

                return true;
            }
        }

        return false;
    }

    /**
     * Update an existing {@link FolderProperties} with fresh {@link StatusData}.
     *
     * This will force the {@link Geary.FolderProperties.email_total} property to match the
     * {@link status_messages} value.
     */
    public void update_status(StatusData status) {
        set_status_message_count(status.messages, true);
        set_status_unseen(status.unseen);
        recent = status.recent;
        uid_validity = status.uid_validity;
        uid_next = status.uid_next;
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

    public void set_status_unseen(int count) {
        // drop unknown counts, especially if known is held here
        if (count < 0)
            return;

        unseen = count;

        // update base class value (which clients see)
        email_unread = count;
    }

    public void set_from_session_capabilities(Capabilities capabilities) {
        create_never_returns_id = !capabilities.supports_uidplus();
    }
}

