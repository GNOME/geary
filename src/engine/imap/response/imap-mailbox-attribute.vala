/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An IMAP mailbox attribute (flag).
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.2.2]]
 *
 * @see ListCommand
 * @see MailboxInformation
 */

public class Geary.Imap.MailboxAttribute : Geary.Imap.Flag {
    private static MailboxAttribute? _no_inferiors = null;
    public static MailboxAttribute NO_INFERIORS { get {
        if (_no_inferiors == null)
            _no_inferiors = new MailboxAttribute("\\noinferiors");

        return _no_inferiors;
    } }

    private static MailboxAttribute? _nonexistent = null;
    public static MailboxAttribute NONEXISTENT { get {
        return (_nonexistent != null) ? _nonexistent : _nonexistent = new MailboxAttribute("\\NonExistent");
    } }

    private static MailboxAttribute? _no_select = null;
    public static MailboxAttribute NO_SELECT { get {
        if (_no_select == null)
            _no_select = new MailboxAttribute("\\noselect");

        return _no_select;
    } }

    private static MailboxAttribute? _marked = null;
    public static MailboxAttribute MARKED { get {
        if (_marked == null)
            _marked = new MailboxAttribute("\\marked");

        return _marked;
    } }

    private static MailboxAttribute? _unmarked = null;
    public static MailboxAttribute UNMARKED { get {
        if (_unmarked == null)
            _unmarked = new MailboxAttribute("\\unmarked");

        return _unmarked;
    } }

    private static MailboxAttribute? _has_no_children = null;
    public static MailboxAttribute HAS_NO_CHILDREN { get {
        if (_has_no_children == null)
            _has_no_children = new MailboxAttribute("\\hasnochildren");

        return _has_no_children;
    } }

    private static MailboxAttribute? _has_children = null;
    public static MailboxAttribute HAS_CHILDREN { get {
        if (_has_children == null)
            _has_children = new MailboxAttribute("\\haschildren");

        return _has_children;
    } }

    private static MailboxAttribute? _allows_new = null;
    public static MailboxAttribute ALLOWS_NEW { get {
        if (_allows_new == null)
            _allows_new = new MailboxAttribute("\\*");

        return _allows_new;
    } }

    private static MailboxAttribute? _special_use_all = null;
    public static MailboxAttribute SPECIAL_FOLDER_ALL { get {
        return (_special_use_all != null) ? _special_use_all
            : _special_use_all = new MailboxAttribute("\\All");
    } }

    private static MailboxAttribute? _special_use_archive = null;
    public static MailboxAttribute SPECIAL_FOLDER_ARCHIVE { get {
        return (_special_use_archive != null) ? _special_use_archive
            : _special_use_archive = new MailboxAttribute("\\Archive");
    } }

    private static MailboxAttribute? _special_use_drafts = null;
    public static MailboxAttribute SPECIAL_FOLDER_DRAFTS { get {
        return (_special_use_drafts != null) ? _special_use_drafts
            : _special_use_drafts = new MailboxAttribute("\\Drafts");
    } }

    private static MailboxAttribute? _special_use_flagged = null;
    public static MailboxAttribute SPECIAL_FOLDER_FLAGGED { get {
        return (_special_use_flagged != null) ? _special_use_flagged
            : _special_use_flagged = new MailboxAttribute("\\Flagged");
    } }

    private static MailboxAttribute? _special_use_important = null;
    public static MailboxAttribute SPECIAL_FOLDER_IMPORTANT { get {
        return (_special_use_important != null) ? _special_use_important
            : _special_use_important = new MailboxAttribute("\\Important");
    } }

    private static MailboxAttribute? _special_use_junk = null;
    public static MailboxAttribute SPECIAL_FOLDER_JUNK { get {
        return (_special_use_junk != null) ? _special_use_junk
            : _special_use_junk = new MailboxAttribute("\\Junk");
    } }

    private static MailboxAttribute? _special_use_sent = null;
    public static MailboxAttribute SPECIAL_FOLDER_SENT { get {
        return (_special_use_sent != null) ? _special_use_sent
            : _special_use_sent = new MailboxAttribute("\\Sent");
    } }

    private static MailboxAttribute? _special_use_trash = null;
    public static MailboxAttribute SPECIAL_FOLDER_TRASH { get {
        return (_special_use_trash != null) ? _special_use_trash
            : _special_use_trash = new MailboxAttribute("\\Trash");
    } }

    private static MailboxAttribute? _xlist_inbox = null;
    public static MailboxAttribute XLIST_INBOX { get {
        if (_xlist_inbox == null)
            _xlist_inbox = new MailboxAttribute("\\Inbox");

        return _xlist_inbox;
    } }

    private static MailboxAttribute? _xlist_all_mail = null;
    public static MailboxAttribute XLIST_ALL_MAIL { get {
        if (_xlist_all_mail == null)
            _xlist_all_mail = new MailboxAttribute("\\AllMail");

        return _xlist_all_mail;
    } }

    private static MailboxAttribute? _xlist_spam = null;
    public static MailboxAttribute XLIST_SPAM { get {
        if (_xlist_spam == null)
            _xlist_spam = new MailboxAttribute("\\Spam");

        return _xlist_spam;
    } }

    private static MailboxAttribute? _xlist_starred = null;
    public static MailboxAttribute XLIST_STARRED { get {
        if (_xlist_starred == null)
            _xlist_starred = new MailboxAttribute("\\Starred");

        return _xlist_starred;
    } }


    public MailboxAttribute(string value) {
        base (value);
    }

    // Call these at init time to prevent thread issues
    internal static void init() {
        MailboxAttribute to_init = NO_INFERIORS;
        to_init = NONEXISTENT;
        to_init = NO_SELECT;
        to_init = MARKED;
        to_init = UNMARKED;
        to_init = HAS_NO_CHILDREN;
        to_init = HAS_CHILDREN;
        to_init = ALLOWS_NEW;
        to_init = SPECIAL_FOLDER_ALL;
        to_init = SPECIAL_FOLDER_ARCHIVE;
        to_init = SPECIAL_FOLDER_DRAFTS;
        to_init = SPECIAL_FOLDER_FLAGGED;
        to_init = SPECIAL_FOLDER_IMPORTANT;
        to_init = SPECIAL_FOLDER_JUNK;
        to_init = SPECIAL_FOLDER_SENT;
        to_init = SPECIAL_FOLDER_TRASH;
        to_init = XLIST_ALL_MAIL;
        to_init = XLIST_INBOX;
        to_init = XLIST_SPAM;
        to_init = XLIST_STARRED;
    }

}
