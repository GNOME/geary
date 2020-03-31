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
     * Search the {@link MailboxAttributes} looking for an XLIST-style
     * {@link Geary.SpecialFolderType}.
     */
    public Geary.SpecialFolderType get_special_folder_type() {
        if (contains(MailboxAttribute.SPECIAL_FOLDER_INBOX))
            return Geary.SpecialFolderType.INBOX;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_ALL_MAIL))
            return Geary.SpecialFolderType.ALL_MAIL;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_TRASH))
            return Geary.SpecialFolderType.TRASH;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_DRAFTS))
            return Geary.SpecialFolderType.DRAFTS;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_SENT))
            return Geary.SpecialFolderType.SENT;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_JUNK))
            return Geary.SpecialFolderType.JUNK;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_SPAM))
            return Geary.SpecialFolderType.JUNK;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_STARRED))
            return Geary.SpecialFolderType.FLAGGED;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_IMPORTANT))
            return Geary.SpecialFolderType.IMPORTANT;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_ARCHIVE))
            return Geary.SpecialFolderType.ARCHIVE;

        if (contains(MailboxAttribute.SPECIAL_FOLDER_FLAGGED))
            return Geary.SpecialFolderType.FLAGGED;

        return Geary.SpecialFolderType.NONE;
    }
}

