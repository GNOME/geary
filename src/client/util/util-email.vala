/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
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

    /**
     * Returns the subject for an email stripped of prefixes.
     *
     * If the email has no subject, returns a localised placeholder.
     */
    public string strip_subject_prefixes(Geary.EmailHeaderSet email) {
        string? cleaned = null;
        if (email.subject != null) {
            cleaned = email.subject.strip_prefixes();
        }
        return (
            !Geary.String.is_empty_or_whitespace(cleaned)
            ? cleaned
            // Translators: Label used when an email has a missing or
            // an empty subject
            : _("(No subject)")
        );
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
     * serialised by {@link
     * Geary.RFC822.MailboxAddress.to_short_display}, if the list
     * contains more mailboxes then an indication of how many
     * additional are present.
     */
    public string to_short_recipient_display(Geary.EmailHeaderSet headers) {
        Geary.RFC822.MailboxAddresses? mailboxes = null;
        int total = 0;
        if (headers.to != null) {
            mailboxes = headers.to;
            total += headers.to.size;
        }
        if (headers.cc != null) {
            if (mailboxes == null) {
                mailboxes = headers.cc;
            }
            total += headers.cc.size;
        }
        if (headers.bcc != null) {
            if (mailboxes == null) {
                mailboxes = headers.bcc;
            }
            total += headers.bcc.size;
        }

        /// Translators: This is shown for displaying a list of email
        /// recipients that happens to be empty, i.e. contains no
        /// email addresses.
        string display = _("(No recipients)");
        if (total > 0) {
            // Always mention the first recipient
            display = mailboxes.get(0).to_short_display();

            if (total > 1) {
                /// Translators: This is used for displaying a short
                /// list of email recipients lists with two or more
                /// addresses. The first (string) substitution is
                /// address of the first, the second substitution is
                /// the number of n - 1 remaining recipients.
                display = GLib.ngettext(
                    "%s and %d other",
                    "%s and %d others",
                    total - 1
                ).printf(display, total - 1);
            }
        }
        return display;
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
                                        Geary.RFC822.TextFormat format) {
        string quoted = "";
        if (email.body != null || quote != null) {
            /// GLib g_date_time_format format string for the date and
            /// time that a message being replied to was
            /// received. This should be roughly similar to an RFC
            /// 822-style date header value with optional additional
            /// punctuation for readability. Note that this date may
            /// be sent to someone in a different locale than the
            /// sender, so should be unambiguous (for example, do not
            /// use mm/dd/yyyy since it could be confused with
            /// dd/mm/yyyy) and must include the time zone.
            string date_format = _("%a, %b %-e %Y at %X %Z");

            if (email.date != null && email.from != null) {
                /// The quoted header for a message being replied to.
                /// %1$s will be substituted for the date, and %2$s
                /// will be substituted for the original sender.
                string QUOTED_LABEL = _("On %1$s, %2$s wrote:");
                quoted += QUOTED_LABEL.printf(
                    email.date.value.format(date_format),
                    Geary.RFC822.Utils.email_addresses_for_reply(
                        email.from, format
                    )
                );
            } else if (email.from != null) {
                /// The quoted header for a message being replied to
                /// (in case the date is not known).  %s will be
                /// replaced by the original sender.
                string QUOTED_LABEL = _("%s wrote:");
                quoted += QUOTED_LABEL.printf(
                    Geary.RFC822.Utils.email_addresses_for_reply(
                        email.from, format
                    )
                );
            } else if (email.date != null) {
                /// The quoted header for a message being replied to
                /// (in case the sender is not known).  %s will be
                /// replaced by the original date
                string QUOTED_LABEL = _("On %s:");
                quoted += QUOTED_LABEL.printf(
                    email.date.value.format(date_format)
                );
            }

            quoted += "<br />";
            try {
                quoted += quote_body(email, quote, true, format);
            } catch (Error err) {
                debug("Failed to quote body for replying: %s".printf(err.message));
            }
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

}


/**
 * Parses a human-entered email query string as a query expression.
 *
 * @see Geary.SearchQuery.Term
 */
public class Util.Email.SearchExpressionFactory : Geary.BaseObject {


    private const unichar OPERATOR_SEPARATOR = ':';
    private const string OPERATOR_TEMPLATE = "%s:%s";


    private delegate Geary.SearchQuery.Term? OperatorFactory(
        string value,
        bool is_quoted
    );


    private class FactoryContext {


        public unowned OperatorFactory factory;


        public FactoryContext(OperatorFactory factory) {
            this.factory = factory;
        }

    }


    private class Tokeniser {


        [Flags]
        private enum CharStatus { NONE, IN_WORD, END_WORD; }


        // These characters are chosen for being commonly used to
        // continue a single word (such as extended last names,
        // i.e. "Lars-Eric") or in terms commonly searched for in an
        // email client, i.e. unadorned mailbox addresses.  Note that
        // characters commonly used for wildcards or that would be
        // interpreted as wildcards by SQLite are not included here.
        private const unichar[] CONTINUATION_CHARS = {
            '-', '_', '.', '@'
        };

        public bool has_next {
            get { return (this.current_pos < this.query.length); }
        }

        public bool is_at_word {
            get { return CharStatus.IN_WORD in this.char_status[this.current_pos]; }
        }

        public bool is_at_quote {
            get { return (this.c == '"'); }
        }

        public unichar current_character { get { return this.c; } }


        private string query;
        private int current_pos = -1;
        private int next_pos = 0;

        private unichar c = 0;
        private CharStatus[] char_status;


        public Tokeniser(string query) {
            this.query = query;

            // Break up search string into individual words and/or
            // operators. Can't simply break on space or
            // non-alphanumeric chars since some languages don't use
            // spaces, so use ICU for its support for the Unicode UAX
            // #29 word boundary spec and dictionary-based breaking
            // for languages that do not use spaces for work breaks.

            this.char_status = new CharStatus[query.length + 1];

            var icu_err = Icu.ErrorCode.ZERO_ERROR;
            var icu_text = Icu.Text.open_utf8(null, this.query.data, ref icu_err);
            var word_breaker = Icu.BreakIterator.open(
                WORD, "en", null, -1, ref icu_err
            );
            word_breaker.set_utext(icu_text, ref icu_err);

            int32 prev_index = 0;
            var current_index = word_breaker.first();
            var status = 0;
            while (current_index != Icu.BreakIterator.DONE) {
                status = word_breaker.rule_status;
                if (!(status >= Icu.BreakIterator.WordBreak.NONE &&
                      status < Icu.BreakIterator.WordBreak.NONE_LIMIT)) {
                    for (int i = prev_index; i < current_index; i++) {
                        this.char_status[i] |= IN_WORD;
                    }
                    this.char_status[current_index] |= END_WORD;
                }

                prev_index = current_index;
                current_index = word_breaker.next();
            }

            consume_char();
        }

        public void consume_char() {
            var current_pos = this.next_pos;
            this.query.get_next_char(ref this.next_pos, out this.c);
            this.current_pos = current_pos;
        }

        public void skip_to_next() {
            while (this.has_next && !this.is_at_quote && !this.is_at_word) {
                consume_char();
            }
        }

        public string consume_word() {
            var start = this.current_pos;
            consume_char();
            while (this.has_next &&
                   this.c != OPERATOR_SEPARATOR &&
                   (this.c in CONTINUATION_CHARS ||
                    !(CharStatus.END_WORD in this.char_status[this.current_pos]))) {
                consume_char();
            }
            return this.query.slice(start, this.current_pos);
        }

        public string consume_quote() {
            consume_char(); // skip the leading quote
            var start = this.current_pos;
            var last_c = this.c;
            while (this.has_next && (this.c != '"' || last_c == '\\')) {
                consume_char();
            }
            var quote = this.query.slice(start, this.current_pos);
            consume_char(); // skip the trailing quote
            return quote;
        }

    }


    public Geary.SearchQuery.Strategy default_strategy { get; private set; }

    public Geary.AccountInformation account { get; private set; }

    // Maps of localised search operator names and values to their
    // internal forms
    private Gee.Map<string,FactoryContext> text_operators =
            new Gee.HashMap<string,FactoryContext>();
    private Gee.Map<string,FactoryContext> boolean_operators =
            new Gee.HashMap<string,FactoryContext>();
    private Gee.Set<string> search_op_to_me = new Gee.HashSet<string>();
    private Gee.Set<string> search_op_from_me = new Gee.HashSet<string>();


    public SearchExpressionFactory(Geary.SearchQuery.Strategy default_strategy,
                                   Geary.AccountInformation account) {
        this.default_strategy = default_strategy;
        this.account = account;
        construct_factories();
    }

    /** Constructs a search expression from the given query string. */
    public Gee.List<Geary.SearchQuery.Term> parse_query(string query) {
        var operands = new Gee.LinkedList<Geary.SearchQuery.Term>();
        var tokens = new Tokeniser(query);
        while (tokens.has_next) {
            if (tokens.is_at_word) {
                Geary.SearchQuery.Term? op = null;
                var word = tokens.consume_word();
                if (tokens.current_character == OPERATOR_SEPARATOR &&
                    tokens.has_next) {
                    op = new_extended_operator(word, tokens);
                }
                if (op == null) {
                    op = new_text_all_operator(word, false);
                }
                operands.add(op);
            } else if (tokens.is_at_quote) {
                operands.add(
                    new_text_all_operator(tokens.consume_quote(), true)
                );
            } else {
                tokens.skip_to_next();
            }
        }

        return operands;
    }

    private Geary.SearchQuery.Term? new_extended_operator(string name,
                                                          Tokeniser tokens) {
        Geary.SearchQuery.Term? op = null;

        // consume the ':'
        tokens.consume_char();

        bool is_quoted = false;
        string? value = null;
        if (tokens.is_at_word) {
            value = tokens.consume_word();
        } else if (tokens.is_at_quote) {
            value = tokens.consume_quote();
            is_quoted = true;
        }

        FactoryContext? context = null;
        if (value != null) {
            context = this.text_operators[name];
            if (context == null) {
                context = this.boolean_operators[
                    OPERATOR_TEMPLATE.printf(name, value)
                ];
            }
        }

        if (context != null) {
            op = context.factory(value, is_quoted);
        }

        if (op == null) {
            // Still no operator, so the name or value must have been
            // invalid. Repair by treating each as separate ops, if
            // present.
            var term = (
                value == null
                ? "%s:".printf(name)
                : "%s:%s".printf(name, value)
            );
            op = new_text_all_operator(term, false);
        }

        return op;
    }

    private inline Geary.SearchQuery.Strategy get_matching_strategy(bool is_quoted) {
        return (
            is_quoted
            ? Geary.SearchQuery.Strategy.EXACT
            : this.default_strategy
        );
    }

    private Gee.List<string> get_account_addresses() {
        Gee.List<Geary.RFC822.MailboxAddress>? mailboxes =
            this.account.sender_mailboxes;
        var addresses = new Gee.LinkedList<string>();
        if (mailboxes != null) {
            foreach (var mailbox in mailboxes) {
                addresses.add(mailbox.address);
            }
        }
        return addresses;
    }

    private void construct_factories() {
        // Maps of possibly translated search operator names and values
        // to English/internal names and values. We include the
        // English version anyway so that when translations provide a
        // localised version of the operator names but have not also
        // translated the user manual, the English version in the
        // manual still works.

        // Text operators
        ///////////////////////////////////////////////////////////

        FactoryContext attachment_name = new FactoryContext(
            this.new_text_attachment_name_operator
        );
        this.text_operators.set("attachment", attachment_name);
        /// Translators: Can be typed in the search box like
        /// "attachment:file.txt" to find messages with attachments
        /// with a particular name.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "attachment"),
                                attachment_name);

        FactoryContext bcc = new FactoryContext(this.new_text_bcc_operator);
        this.text_operators.set("bcc", bcc);
        /// Translators: Can be typed in the search box like
        /// "bcc:johndoe@example.com" to find messages bcc'd to a
        /// particular person.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "bcc"), bcc);

        FactoryContext body = new FactoryContext(this.new_text_body_operator);
        this.text_operators.set("body", body);
        /// Translators: Can be typed in the search box like
        /// "body:word" to find "word" only if it occurs in the body
        /// of a message.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "body"), body);

        FactoryContext cc = new FactoryContext(this.new_text_cc_operator);
        this.text_operators.set("cc", cc);
        /// Translators: Can be typed in the search box like
        /// "cc:johndoe@example.com" to find messages cc'd to a
        /// particular person.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "cc"), cc);

        FactoryContext from = new FactoryContext(this.new_text_from_operator);
        this.text_operators.set("from", from);
        /// Translators: Can be typed in the search box like
        /// "from:johndoe@example.com" to find messages from a
        /// particular sender.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "from"), from);

        FactoryContext subject = new FactoryContext(
            this.new_text_subject_operator
        );
        this.text_operators.set("subject", subject);
        /// Translators: Can be typed in the search box like
        /// "subject:word" to find "word" only if it occurs in the
        /// subject of a message.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "subject"), subject);

        FactoryContext to = new FactoryContext(this.new_text_to_operator);
        this.text_operators.set("to", to);
        /// Translators: Can be typed in the search box like
        /// "to:johndoe@example.com" to find messages received by a
        /// particular person.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.text_operators.set(C_("Search operator", "to"), to);

        /// Translators: Can be typed in the search box after "to:",
        /// "cc:" and "bcc:" e.g.: "to:me". Matches conversations that
        /// are addressed to the user.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.search_op_to_me.add(
            C_("Search operator value - mail addressed to the user", "me")
        );
        this.search_op_to_me.add("me");

        /// Translators: Can be typed in the search box after "from:"
        /// i.e.: "from:me". Matches conversations were sent by the
        /// user.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        this.search_op_from_me.add(
            C_("Search operator value - mail sent by the user", "me")
        );
        this.search_op_from_me.add("me");

        // Boolean operators
        ///////////////////////////////////////////////////////////

        /// Translators: Can be typed in the search box like
        /// "is:unread" to find messages that are read, unread, or
        /// starred.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        string bool_is_name = C_("Search operator", "is");

        /// Translators: Can be typed in the search box after "is:"
        /// i.e.: "is:unread". Matches conversations that are flagged
        /// unread.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        string bool_is_unread_value = C_("'is:' search operator value", "unread");

        /// Translators: Can be typed in the search box after "is:"
        /// i.e.: "is:read". Matches conversations that are flagged as
        /// read.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        string bool_is_read_value = C_("'is:' search operator value", "read");

        /// Translators: Can be typed in the search box after "is:"
        /// i.e.: "is:starred". Matches conversations that are flagged
        /// as starred.
        ///
        /// The translated string must be a single word (use '-', '_'
        /// or similar to combine words into one), should be short,
        /// and also match the translation in "search.page" of the
        /// Geary User Guide.
        string bool_is_starred_value = C_("'is:' search operator value", "starred");

        FactoryContext is_unread = new FactoryContext(
            this.new_boolean_unread_operator
        );
        this.boolean_operators.set("is:unread", is_unread);
        this.boolean_operators.set(
            OPERATOR_TEMPLATE.printf(
                bool_is_name, bool_is_unread_value
            ), is_unread
        );

        FactoryContext is_read = new FactoryContext(
            this.new_boolean_read_operator
        );
        this.boolean_operators.set("is:read", is_read);
        this.boolean_operators.set(
            OPERATOR_TEMPLATE.printf(
                bool_is_name, bool_is_read_value
            ), is_read
        );

        FactoryContext is_starred = new FactoryContext(
            this.new_boolean_starred_operator
        );
        this.boolean_operators.set("is:starred", is_starred);
        this.boolean_operators.set(
            OPERATOR_TEMPLATE.printf(
                bool_is_name, bool_is_starred_value
            ), is_starred
        );
    }

    private Geary.SearchQuery.Term? new_text_all_operator(
        string value, bool is_quoted
    ) {
        return new Geary.SearchQuery.EmailTextTerm(
            ALL, get_matching_strategy(is_quoted), value
        );
    }

    private Geary.SearchQuery.Term? new_text_attachment_name_operator(
        string value, bool is_quoted
    ) {
        return new Geary.SearchQuery.EmailTextTerm(
            ATTACHMENT_NAME, get_matching_strategy(is_quoted), value
        );
    }

    private Geary.SearchQuery.Term? new_text_bcc_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted && value in this.search_op_to_me) {
            op = new Geary.SearchQuery.EmailTextTerm.disjunction(
                BCC, EXACT, get_account_addresses()
            );
        } else {
            op = new Geary.SearchQuery.EmailTextTerm(
                BCC, EXACT, value
            );
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_text_body_operator(
        string value, bool is_quoted
    ) {
        return new Geary.SearchQuery.EmailTextTerm(
            BODY, get_matching_strategy(is_quoted), value
        );
    }

    private Geary.SearchQuery.Term? new_text_cc_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted && value in this.search_op_to_me) {
            op = new Geary.SearchQuery.EmailTextTerm.disjunction(
                CC, EXACT, get_account_addresses()
            );
        } else {
            op = new Geary.SearchQuery.EmailTextTerm(
                CC, get_matching_strategy(is_quoted), value
            );
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_text_from_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted && value in this.search_op_from_me) {
            op = new Geary.SearchQuery.EmailTextTerm.disjunction(
                FROM, EXACT, get_account_addresses()
            );
        } else {
            op = new Geary.SearchQuery.EmailTextTerm(FROM, EXACT, value);
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_text_subject_operator(
        string value, bool is_quoted
    ) {
        return new Geary.SearchQuery.EmailTextTerm(
            SUBJECT, get_matching_strategy(is_quoted), value
        );
    }

    private Geary.SearchQuery.Term? new_text_to_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted && value in this.search_op_to_me) {
            op = new Geary.SearchQuery.EmailTextTerm.disjunction(
                TO, EXACT, get_account_addresses()
            );
        } else {
            op = new Geary.SearchQuery.EmailTextTerm(
                TO, EXACT, value
            );
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_boolean_unread_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted) {
            op = new Geary.SearchQuery.EmailFlagTerm(Geary.EmailFlags.UNREAD);
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_boolean_read_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted) {
            op = new Geary.SearchQuery.EmailFlagTerm(Geary.EmailFlags.UNREAD);
            op.is_negated = true;
        }
        return op;
    }

    private Geary.SearchQuery.Term? new_boolean_starred_operator(
        string value, bool is_quoted
    ) {
        Geary.SearchQuery.Term? op = null;
        if (!is_quoted) {
            op = new Geary.SearchQuery.EmailFlagTerm(Geary.EmailFlags.FLAGGED);
        }
        return op;
    }

}
