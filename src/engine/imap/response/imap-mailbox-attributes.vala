/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of {@link MailboxAttribute}s.
 *
 * @see ListCommand
 * @see MailboxInformation
 */

public class Geary.Imap.MailboxAttributes : Geary.Imap.Flags {
    /**
     * True if the mailbox should not be accessed via SELECT, EXAMINE, or STATUS, i.e. is a
     * "no-select" mailbox.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.2.2]] and
     * [[http://tools.ietf.org/html/rfc5258#section-3]]
     */
    public bool is_no_select { get {
        return contains(MailboxAttribute.NO_SELECT) || contains(MailboxAttribute.NONEXISTENT);
    } }

    public MailboxAttributes(Gee.Collection<MailboxAttribute> attrs) {
        base (attrs);
    }

    /**
     * Create {@link MailboxAttributes} from a {@link ListParameter} of attribute strings.
     */
    public static MailboxAttributes from_list(ListParameter listp) throws ImapError {
        Gee.Collection<MailboxAttribute> list = new Gee.ArrayList<MailboxAttribute>();
        for (int ctr = 0; ctr < listp.size; ctr++)
            list.add(new MailboxAttribute(listp.get_as_string(ctr).ascii));

        return new MailboxAttributes(list);
    }

    /**
     * Create {@link MailboxAttributes} from a flat string of space-delimited attributes.
     */
    public static MailboxAttributes deserialize(string? str) {
        if (String.is_empty(str))
            return new MailboxAttributes(new Gee.ArrayList<MailboxAttribute>());

        string[] tokens = str.split(" ");

        Gee.Collection<MailboxAttribute> attrs = new Gee.ArrayList<MailboxAttribute>();
        foreach (string token in tokens)
            attrs.add(new MailboxAttribute(token));

        return new MailboxAttributes(attrs);
    }

    /**
     * Returns the special use specified for the mailbox.
     *
     * If no special use is set, returns {@link
     * Geary.Folder.SpecialUse.NONE}.
     */
    public Geary.Folder.SpecialUse get_special_use() {
        if (contains(MailboxAttribute.SPECIAL_FOLDER_ALL))
            return ALL_MAIL;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_ARCHIVE))
            return ARCHIVE;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_DRAFTS))
            return DRAFTS;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_FLAGGED))
            return FLAGGED;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_IMPORTANT))
            return IMPORTANT;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_JUNK))
            return JUNK;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_SENT))
            return SENT;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_TRASH))
            return TRASH;

        if (contains(MailboxAttribute.XLIST_ALL_MAIL))
            return ALL_MAIL;

        if (contains(MailboxAttribute.XLIST_INBOX))
            return INBOX;

        if (contains(MailboxAttribute.XLIST_SPAM))
            return JUNK;

        if (contains(MailboxAttribute.XLIST_STARRED))
            return FLAGGED;

        return NONE;
    }

}
