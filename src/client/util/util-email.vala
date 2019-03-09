/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Util.Email {

    public int compare_conversation_ascending(Geary.App.Conversation a,
                                              Geary.App.Conversation b) {
        Geary.Email? a_latest = a.get_latest_recv_email(
            Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER
        );
        Geary.Email? b_latest = b.get_latest_recv_email(
            Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER
        );

        if (a_latest == null) {
            return (b_latest == null) ? 0 : -1;
        } else if (b_latest == null) {
            return 1;
        }

        // use date-received so newly-arrived messages float to the
        // top, even if they're send date was earlier (think of
        // mailing lists that batch up forwarded mail)
        return Geary.Email.compare_recv_date_ascending(a_latest, b_latest);
    }

    public int compare_conversation_descending(Geary.App.Conversation a,
                                               Geary.App.Conversation b) {
        return compare_conversation_ascending(b, a);
    }

    /** Returns the stripped subject line, or a placeholder if none. */
    public string strip_subject_prefixes(Geary.Email email) {
        string? cleaned = (email.subject != null) ? email.subject.strip_prefixes() : null;
        return !Geary.String.is_empty(cleaned) ? cleaned : _("(no subject)");
    }

    /**
     * Returns a shortened recipient list suitable for display.
     *
     * This is useful in case there are a lot of recipients, or there
     * is little room for the display.
     *
     * @return a string containing at least the first mailbox
     * serialised by {@link MailboxAddress.to_short_display}, if the
     * list contains more mailboxes then an indication of how many
     * additional are present.
     */
    public string to_short_recipient_display(Geary.RFC822.MailboxAddresses mailboxes) {
        if (mailboxes.size == 0) {
            // Translators: This is shown for displaying a list of
            // email recipients that happens to be empty,
            // i.e. contains no email addresses.
            return _("(No recipients)");
        }

        // Always mention the first recipient
        string first_recipient = mailboxes.get(0).to_short_display();
        if (mailboxes.size == 1)
            return first_recipient;

        // Translators: This is used for displaying a short list of
        // email recipients lists with two or more addresses. The
        // first (string) substitution is address of the first, the
        // second substitution is the number of n - 1 remaining
        // recipients.
        return GLib.ngettext(
            "%s and %d other",
            "%s and %d others",
            mailboxes.size - 1
        ).printf(first_recipient, mailboxes.size - 1);
    }

}
