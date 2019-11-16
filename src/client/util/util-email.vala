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
     * Returns a mailbox for the primary originator of an email.
     *
     * RFC 822 allows multiple and absent From header values, and
     * software such as Mailman and GitLab will mangle the names in
     * From mailboxes. This provides a canonical means to obtain a
     * mailbox (that is, name and email address) for the first
     * originator, and with the mailbox's name having been fixed up
     * where possible.
     *
     * The first From mailbox is used and de-mangled if found, if not
     * the Sender mailbox is used if present, else the first Reply-To
     * mailbox is used.
     */
    public Geary.RFC822.MailboxAddress?
        get_primary_originator(Geary.EmailHeaderSet email) {
        Geary.RFC822.MailboxAddress? primary = null;
        if (email.from != null && email.from.size > 0) {
            // We have a From address, so attempt to de-mangle it
            Geary.RFC822.MailboxAddresses? from = email.from;

            string from_name = "";
            if (from != null && from.size > 0) {
                primary = from[0];
                from_name = primary.name ?? "";
            }

            Geary.RFC822.MailboxAddresses? reply_to = email.reply_to;
            Geary.RFC822.MailboxAddress? primary_reply_to = null;
            string reply_to_name = "";
            if (reply_to != null && reply_to.size > 0) {
                primary_reply_to = reply_to[0];
                reply_to_name = primary_reply_to.name ?? "";
            }

            // Spaces are important
            const string VIA = " via ";

            if (reply_to_name != "" && from_name.has_prefix(reply_to_name)) {
                // Mailman sometimes sends the true originator as the
                // Reply-To for the email
                primary = primary_reply_to;
            } else if (VIA in from_name) {
                // Mailman, GitLib, Discourse and others send the
                // originator's name prefixing something starting with
                // "via".
                primary = new Geary.RFC822.MailboxAddress(
                    from_name.split(VIA, 2)[0], primary.address
                );
            }
        } else if (email.sender != null) {
            primary = email.sender;
        } else if (email.reply_to != null && email.reply_to.size > 0) {
            primary = email.reply_to[0];
        }

        return primary;
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

    /**
     * Returns a quoted text string needed for a reply.
     *
     * If there's no message body in the supplied email or quote text, this
     * function will return the empty string.
     *
     * If html_format is true, the message will be quoted in HTML format.
     * Otherwise it will be in plain text.
     */
    public string quote_email_for_reply(Geary.Email email,
                                        string? quote,
                                        Util.Date.ClockFormat clock_format,
                                        Geary.RFC822.TextFormat format) {
        if (email.body == null && quote == null)
            return "";

        string quoted = "";

        string DATE_FORMAT = Util.Date.get_full_date(clock_format);

        if (email.date != null && email.from != null) {
            /// The quoted header for a message being replied to.
            /// %1$s will be substituted for the date, and %2$s will be substituted for
            /// the original sender.
            string QUOTED_LABEL = _("On %1$s, %2$s wrote:");
            quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT),
                                          Geary.RFC822.Utils.email_addresses_for_reply(email.from, format));

        } else if (email.from != null) {
            /// The quoted header for a message being replied to (in case the date is not known).
            /// %s will be replaced by the original sender.
            string QUOTED_LABEL = _("%s wrote:");
            quoted += QUOTED_LABEL.printf(Geary.RFC822.Utils.email_addresses_for_reply(email.from, format));

        } else if (email.date != null) {
            /// The quoted header for a message being replied to (in case the sender is not known).
            /// %s will be replaced by the original date
            string QUOTED_LABEL = _("On %s:");
            quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT));
        }

        quoted += "<br />";
        try {
            quoted += quote_body(email, quote, true, format);
        } catch (Error err) {
            debug("Failed to quote body for replying: %s".printf(err.message));
        }

        return quoted;
    }

    /**
     * Returns a quoted text string needed for a forward.
     *
     * If there's no message body in the supplied email or quote text, this
     * function will return the empty string.
     *
     * If html_format is true, the message will be quoted in HTML format.
     * Otherwise it will be in plain text.
     */
    public string quote_email_for_forward(Geary.Email email, string? quote, Geary.RFC822.TextFormat format) {
        if (email.body == null && quote == null)
            return "";

        const string HEADER_FORMAT = "%s %s\n";

        string quoted = _("---------- Forwarded message ----------");
        quoted += "\n";
        string from_line = Geary.RFC822.Utils.email_addresses_for_reply(email.from, format);
        if (!Geary.String.is_empty_or_whitespace(from_line)) {
            // Translators: Human-readable version of the RFC 822 From header
            quoted += HEADER_FORMAT.printf(_("From:"), from_line);
        }
        // Translators: Human-readable version of the RFC 822 Subject header
        quoted += HEADER_FORMAT.printf(_("Subject:"), email.subject != null ? email.subject.to_string() : "");
        // Translators: Human-readable version of the RFC 822 Date header
        quoted += HEADER_FORMAT.printf(_("Date:"), email.date != null ? email.date.to_string() : "");
        string to_line = Geary.RFC822.Utils.email_addresses_for_reply(email.to, format);
        if (!Geary.String.is_empty_or_whitespace(to_line)) {
            // Translators: Human-readable version of the RFC 822 To header
            quoted += HEADER_FORMAT.printf(_("To:"), to_line);
        }
        string cc_line = Geary.RFC822.Utils.email_addresses_for_reply(email.cc, format);
        if (!Geary.String.is_empty_or_whitespace(cc_line)) {
            // Translators: Human-readable version of the RFC 822 CC header
            quoted += HEADER_FORMAT.printf(_("Cc:"), cc_line);
        }
        quoted += "\n";  // A blank line between headers and body
        quoted = quoted.replace("\n", "<br />");
        try {
            quoted += quote_body(email, quote, false, format);
        } catch (Error err) {
            debug("Failed to quote body for forwarding: %s".printf(err.message));
        }
        return quoted;
    }

    private string quote_body(Geary.Email email,
                              string? html_quote,
                              bool use_quotes,
                              Geary.RFC822.TextFormat format)
        throws Error {
        Geary.RFC822.Message? message = email.get_message();
        string? body_text = null;
        if (Geary.String.is_empty(html_quote)) {
            switch (format) {
                case Geary.RFC822.TextFormat.HTML:
                    body_text = message.has_html_body()
                        ? message.get_html_body(null)
                        : message.get_plain_body(true, null);
                    break;

                case Geary.RFC822.TextFormat.PLAIN:
                    body_text = message.has_plain_body()
                        ? message.get_plain_body(true, null)
                        : message.get_html_body(null);
                    break;
            }
        } else {
            body_text = html_quote;
        }

        // Wrap the whole thing in a blockquote.
        if (use_quotes && !Geary.String.is_empty(body_text))
            body_text = "<blockquote type=\"cite\">%s</blockquote>".printf(body_text);

        return body_text;
    }

    private string shorten_url(string url) {
        string new_url = "";
        if (url.length < 90) {
            new_url = url;
        } else {
            new_url = url.substring(0,40) + "..." + url.substring(-40);
        }
        return new_url;
    }
}
