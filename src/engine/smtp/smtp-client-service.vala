/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018, 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Manages connecting to an SMTP network service.
 *
 * This class maintains a queue of email messages to be delivered, and
 * opens SMTP connections to deliver queued messages as needed.
 */
public class Geary.Smtp.ClientService : Geary.ClientService {


    /** The GLib logging domain used for SMTP sub-system logging. */
    public const string LOGGING_DOMAIN = Logging.DOMAIN + ".Smtp";

    /** The GLib logging domain used for SMTP protocol logging. */
    public const string PROTOCOL_LOGGING_DOMAIN = Logging.DOMAIN + ".Smtp.Net";


    // Used solely for debugging, hence "(no subject)" not marked for
    // translation
    private static string email_subject(EmailHeaderSet email) {
        return (
            email.subject != null && !String.is_empty(email.subject.to_string()))
            ? email.subject.to_string()
            : "(no subject)";
    }


    /** Folder used for storing and retrieving queued mail. */
    public Outbox.Folder? outbox { get; internal set; default = null; }

    /** Progress monitor indicating when email is being sent. */
    public ProgressMonitor sending_monitor {
        get;
        private set;
        default = new SimpleProgressMonitor(ProgressType.ACTIVITY);
    }

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return LOGGING_DOMAIN; }
    }

    private Account owner { get { return this.outbox.account; } }

    private Nonblocking.Queue<EmailIdentifier> outbox_queue =
        new Nonblocking.Queue<EmailIdentifier>.fifo();
    private Cancellable? queue_cancellable = null;

    /** Emitted when the manager has sent an email. */
    public signal void email_sent(Geary.Email email);

    /** Emitted when an error occurred sending an email. */
    public signal void report_problem(Geary.ProblemReport problem);


    public ClientService(AccountInformation account,
                         ServiceInformation service,
                         Endpoint remote) {
        base(account, service, remote);
    }

    /**
     * Starts the manager opening IMAP client sessions.
     */
    public override async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield this.outbox.open_async(Folder.OpenFlags.NONE, cancellable);
        yield this.fill_outbox_queue(cancellable);
        notify_started();
    }

    /**
     * Stops the manager running, closing any existing sessions.
     */
    public override async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        notify_stopped();
        this.stop_postie();
        // Wait for the postie to actually stop before closing the
        // folder so w don't interrupt e.g. sending/saving/deleting
        // mail
        while (this.queue_cancellable != null) {
            GLib.Idle.add(this.stop.callback);
            yield;
        }
        yield this.outbox.close_async(cancellable);
    }

    /**
     * Saves and queues email for immediate delivery.
     *
     * This is a convenience method that calls {@link save_email} then
     * {@link queue_email} with the resulting id.
     */
    public async void send_email(Geary.ComposedEmail composed,
                                 GLib.Cancellable? cancellable)
        throws GLib.Error {
        queue_email(yield save_email(composed, cancellable));
    }

    /**
     * Saves a composed email in the outbox.
     *
     * This sets a suitable MessageID header for the message, then
     * saves the updated message in {@link outbox}. Returns the
     * identifier for the saved email, suitable for use with {@link
     * queue_email}.
     *
     * @see send_email
     */
    public async EmailIdentifier save_email(Geary.ComposedEmail composed,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("Saving composed email: %s", email_subject(composed));

        // Detect server encoding constraint
        GMime.EncodingConstraint constraint = GMime.EncodingConstraint.7BIT;
        try {

            ClientConnection smtp = new ClientConnection(this.remote);
            yield smtp.connect_async(cancellable);
            yield smtp.say_hello_async(cancellable);
            if (smtp.capabilities.has_capability(Capabilities.8BITMIME)) {
                constraint = GMime.EncodingConstraint.8BIT;
            }
            yield smtp.disconnect_async(cancellable);
        } catch (Error err) {
            // Oh well
        }

        // XXX work out what our public IP address is somehow and use
        // that in preference to the originator's domain
        var from = composed.from;
        var domain = from != null && !from.is_empty
            ? from[0].domain
            : this.account.primary_mailbox.domain;
        Geary.RFC822.Message rfc822 =
            yield new Geary.RFC822.Message.from_composed_email(
                composed,
                GMime.utils_generate_message_id(domain),
                constraint,
                cancellable
            );

        EmailIdentifier id = yield this.outbox.create_email_async(
            rfc822, null, null, cancellable
        );
        debug("Saved composed email as %s", id.to_string());
        return id;
    }

    /**
     * Queues an email for immediate delivery.
     *
     * The given identifier must be for {@link outbox}, for example as
     * given by {@link save_email}.
     *
     * @see send_email
     */
    public void queue_email(EmailIdentifier outbox_identifier) {
        debug("Queuing email for sending: %s", outbox_identifier.to_string());
        this.outbox_queue.send(outbox_identifier);
    }

    /** Starts the postie delivering messages. */
    protected override void became_reachable() {
        this.start_postie.begin();
    }

    /** Stops the postie delivering. */
    protected override void became_unreachable() {
        this.stop_postie();
    }

    /**
     * Starts delivery of messages in the queue.
     */
    private async void start_postie() {
        debug("Starting outbox postie with %u messages queued", this.outbox_queue.size);
        if (this.queue_cancellable != null) {
            return;
        }

        Cancellable cancellable = this.queue_cancellable =
            new GLib.Cancellable();

        // Start the send queue.
        while (!cancellable.is_cancelled()) {
            // yield until a message is ready
            EmailIdentifier id = null;
            bool email_handled = false;
            try {
                id = yield this.outbox_queue.receive(cancellable);
                yield process_email(id, cancellable);
                email_handled = true;
            } catch (SmtpError err) {
                if (err is SmtpError.AUTHENTICATION_FAILED) {
                    notify_authentication_failed();
                } else if (err is SmtpError.STARTTLS_FAILED ||
                           err is SmtpError.NOT_CONNECTED) {
                    notify_connection_failed(new ErrorContext(err));
                } else if (err is SmtpError.PARSE_ERROR ||
                           err is SmtpError.SERVER_ERROR ||
                           err is SmtpError.NOT_SUPPORTED) {
                    notify_unrecoverable_error(new ErrorContext(err));
                }
            } catch (GLib.IOError.CANCELLED err) {
                // Nothing to do here — we're already cancelled.
            } catch (EngineError.NOT_FOUND err) {
                email_handled = true;
                debug("Queued email %s not found in outbox, ignoring: %s",
                      id.to_string(), err.message);
            } catch (GLib.Error err) {
                notify_connection_failed(new ErrorContext(err));
            }
        }

        this.queue_cancellable = null;
        debug("Outbox postie exited");
    }

    /**
     * Stops delivery of messages in the queue.
     */
    private void stop_postie() {
        debug("Stopping outbox postie");
        if (this.queue_cancellable != null) {
            this.queue_cancellable.cancel();
        }
    }

    /**
     * Loads any email in the outbox and adds them to the queue.
     */
    private async void fill_outbox_queue(GLib.Cancellable? cancellable) {
        debug("Filling queue");
        try {
            Gee.List<Email>? queued = yield this.outbox.list_email_by_id_async(
                null,
                int.MAX, // fetch all
                Email.Field.NONE, // ids only
                Folder.ListFlags.OLDEST_TO_NEWEST,
                cancellable
            );
            if (queued != null) {
                foreach (Email email in queued) {
                    this.outbox_queue.send(email.id);
                }
            }
        } catch (Error err) {
            warning("Error filling queue: %s", err.message);
        }
    }

    // Returns true if email was successfully processed, else false
    private async void process_email(EmailIdentifier id, Cancellable cancellable)
        throws GLib.Error {
        // To prevent spurious connection failures, ensure tokens are
        // up-to-date before attempting to send the email
        if (!yield this.account.load_outgoing_credentials(cancellable)) {
            throw new SmtpError.AUTHENTICATION_FAILED("Credentials not loaded");
        }

        Email email = yield this.outbox.fetch_email_async(
            id, Email.Field.ALL, Folder.ListFlags.NONE, cancellable
        );

        if (!email.email_flags.contains(EmailFlags.OUTBOX_SENT)) {
            RFC822.Message message = email.get_message();
            debug("Outbox postie: Sending \"%s\" (ID:%s)...",
                  email_subject(message), email.id.to_string());
            yield send_email_internal(message, cancellable);
            email_sent(email);

            // Mark as sent, so if there's a problem pushing up to
            // Sent, we don't retry sending. Don't pass the
            // cancellable here - if it's been sent we want to try to
            // update the sent flag anyway
            debug("Outbox postie: Marking %s as sent", email.id.to_string());
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.OUTBOX_SENT);
            yield this.outbox.mark_email_async(
                Collection.single(email.id), flags, null, null
            );

            if (cancellable.is_cancelled()) {
                throw new GLib.IOError.CANCELLED("Send has been cancelled");
            }
        }

        // If we get to this point, the message has either been just
        // sent, or previously sent but not saved. So now try flagging
        // as such and saving it if enabled, else sync the folder in
        // case the provider saved it so the new mail shows up.
        if (this.account.save_sent) {
            debug("Outbox postie: Saving %s to sent mail",
                  email.id.to_string());
            yield save_sent_mail(email, cancellable);
        } else {
            debug("Outbox postie: Syncing sent mail to find %s",
                  email.id.to_string());
            yield sync_sent_mail(email, cancellable);
        }

        // Again, don't observe the cancellable here - if it's been
        // send and saved we want to try to remove it anyway.
        debug("Outbox postie: Deleting row %s", email.id.to_string());
        yield this.outbox.remove_email_async(Collection.single(email.id), null);
    }

    private async void send_email_internal(Geary.RFC822.Message rfc822, Cancellable? cancellable)
        throws Error {
        Credentials? login = this.account.get_outgoing_credentials();
        if (login != null && !login.is_complete()) {
            throw new SmtpError.AUTHENTICATION_FAILED("Token not loaded");
        }

        Smtp.ClientSession smtp = new Geary.Smtp.ClientSession(this.remote);
        smtp.set_logging_parent(this);
        sending_monitor.notify_start();

        Error? smtp_err = null;
        try {
            yield smtp.login_async(login, cancellable);
        } catch (Error login_err) {
            debug("SMTP login error: %s", login_err.message);
            smtp_err = login_err;
        }

        if (smtp_err == null) {
            // Determine the SMTP reverse path, this gets used for
            // bounce notifications, etc. Use the sender by default,
            // since if specified the message is explicitly being sent
            // on behalf of someone else.
            RFC822.MailboxAddress? reverse_path = rfc822.sender;
            if (reverse_path == null) {
                // If no sender specified, use the first from address
                // that is accountured for this account.
                if (rfc822.from != null) {
                    foreach (RFC822.MailboxAddress from in rfc822.from) {
                        if (this.account.has_sender_mailbox(from)) {
                            reverse_path = from;
                            break;
                        }
                    }
                }

                if (reverse_path == null) {
                    // Fall back to using the account's primary
                    // mailbox if nether a sender nor a from address
                    // from this account is found.
                    reverse_path = this.account.primary_mailbox;
                }
            }

            // Now send it
            try {
                yield smtp.send_email_async(reverse_path, rfc822, cancellable);
            } catch (Error send_err) {
                debug("SMTP send mail error: %s", send_err.message);
                smtp_err = send_err;
            }
        }

        try {
            // always logout
            yield smtp.logout_async(false, null);
        } catch (Error err) {
            debug("Unable to disconnect from SMTP server %s: %s", smtp.to_string(), err.message);
        }

        sending_monitor.notify_finish();

        if (smtp_err != null)
            throw smtp_err;
    }

    private async void save_sent_mail(Geary.Email message,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.FolderSupport.Create? create = (
            yield this.owner.get_required_special_folder_async(
                SENT, cancellable
            )
        ) as Geary.FolderSupport.Create;
        if (create == null) {
            throw new EngineError.UNSUPPORTED(
                "Save sent mail enabled, but no writable sent mail folder"
            );
        }

        RFC822.Message raw = message.get_message();
        bool open = false;
        try {
            yield create.open_async(NO_DELAY, cancellable);
            open = true;
            yield create.create_email_async(raw, null, null, cancellable);
            yield wait_for_message(create, message, cancellable);
        } finally {
            if (open) {
                try {
                    yield create.close_async(null);
                } catch (Error e) {
                    debug("Error closing folder %s: %s", create.to_string(), e.message);
                }
            }
        }
    }

    private async void sync_sent_mail(Geary.Email message,
                                      GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.Folder sent = this.owner.get_special_folder(SENT);
        if (sent != null) {
            bool open = false;
            try {
                yield sent.open_async(NO_DELAY, cancellable);
                open = true;
                yield sent.synchronise_remote(cancellable);
                yield wait_for_message(sent, message, cancellable);
            } finally {
                if (open) {
                    try {
                        yield sent.close_async(null);
                    } catch (Error e) {
                        debug("Error closing folder %s: %s",
                              sent.to_string(), e.message);
                    }
                }
            }
        }
    }

    // Wait for a sent message to turn up. There's no guarantee how or
    // when a server may make newly saved email show up, so poll for
    // it. :(
    private async void wait_for_message(Folder location,
                                        Email sent,
                                        GLib.Cancellable cancellable)
        throws GLib.Error {
        RFC822.MessageID? id = sent.message_id;
        if (id != null) {
            const int MAX_RETRIES = 3;
            for (int i = 0; i < MAX_RETRIES; i++) {
                Gee.List<Email>? list = yield location.list_email_by_id_async(
                    null, 1, REFERENCES, NONE, cancellable
                );
                if (list != null && !list.is_empty) {
                    Email listed = Collection.first(list);
                    if (listed.message_id != null &&
                        listed.message_id.equal_to(id)) {
                        break;
                    }
                }

                // Wait a second before retrying to give the server
                // some breathing room
                debug("Waiting for sent mail...");
                GLib.Timeout.add_seconds(1, wait_for_message.callback);
                yield;
            }
        }
    }

}
