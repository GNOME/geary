/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
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
internal class Geary.Smtp.ClientService : Geary.ClientService {

    // Min and max times between attempting to re-send after a
    // connection failure.
    private const uint MIN_SEND_RETRY_INTERVAL_SEC = 4;
    private const uint MAX_SEND_RETRY_INTERVAL_SEC = 64;


    // Used solely for debugging, hence "(no subject)" not marked for translation
    private static string message_subject(RFC822.Message message) {
        return (message.subject != null && !String.is_empty(message.subject.to_string()))
            ? message.subject.to_string() : "(no subject)";
    }


    /** Folder used for storing and retrieving queued mail. */
    public Outbox.Folder outbox { get; private set; }

    /** Progress monitor indicating when email is being sent. */
    public ProgressMonitor sending_monitor {
        get;
        private set;
        default = new SimpleProgressMonitor(ProgressType.ACTIVITY);
    }

    private Account owner { get { return this.outbox.account; } }

    private Nonblocking.Queue<EmailIdentifier> outbox_queue =
        new Nonblocking.Queue<EmailIdentifier>.fifo();
    private Cancellable? queue_cancellable = null;

    /** Emitted when the manager has sent an email. */
    public signal void email_sent(Geary.RFC822.Message rfc822);

    /** Emitted when an error occurred sending an email. */
    public signal void report_problem(Geary.ProblemReport problem);


    public ClientService(AccountInformation account,
                         ServiceInformation service,
                         Outbox.Folder outbox) {
        base(account, service);
        this.outbox = outbox;
    }

    /**
     * Starts the manager opening IMAP client sessions.
     */
    public override async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.is_running = true;
        yield this.outbox.open_async(Folder.OpenFlags.NONE, cancellable);
        this.fill_outbox_queue.begin();
        this.endpoint.connectivity.notify["is-reachable"].connect(
            on_reachable_changed
        );
        this.endpoint.connectivity.address_error_reported.connect(
            on_connectivity_error
        );
        this.endpoint.connectivity.check_reachable.begin();
    }

    /**
     * Stops the manager running, closing any existing sessions.
     */
    public override async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.endpoint.connectivity.notify["is-reachable"].disconnect(
            on_reachable_changed
        );
        this.endpoint.connectivity.address_error_reported.disconnect(
            on_connectivity_error
        );
        this.stop_postie();
        yield this.outbox.close_async(cancellable);
        this.is_running = false;
    }

    /**
     * Saves and queues an email in the outbox for delivery.
     */
    public async void queue_email(RFC822.Message rfc822,
                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("Queuing message for sending: %s", message_subject(rfc822));

        EmailIdentifier id = yield this.outbox.create_email_async(
            rfc822, null, null, null, cancellable
        );
        this.outbox_queue.send(id);
    }

    /**
     * Loads any email in the outbox and adds them to the queue.
     */
    private async void fill_outbox_queue() {
        try {
            Gee.List<Email>? queued = yield this.outbox.list_email_by_id_async(
                null,
                int.MAX, // fetch all
                Email.Field.NONE, // ids only
                Folder.ListFlags.OLDEST_TO_NEWEST,
                this.queue_cancellable
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
        uint send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;

        // Start the send queue.
        while (!cancellable.is_cancelled()) {
            // yield until a message is ready
            EmailIdentifier id = null;
            bool email_handled = false;
            try {
                id = yield this.outbox_queue.receive(cancellable);
                email_handled = yield process_email(id, cancellable);
            } catch (SmtpError err) {
                ProblemType problem = ProblemType.GENERIC_ERROR;
                if (err is SmtpError.AUTHENTICATION_FAILED) {
                    problem = ProblemType.LOGIN_FAILED;
                } else if (err is SmtpError.STARTTLS_FAILED) {
                    problem = ProblemType.CONNECTION_ERROR;
                } else if (err is SmtpError.NOT_CONNECTED) {
                    problem = ProblemType.NETWORK_ERROR;
                } else if (err is SmtpError.PARSE_ERROR ||
                           err is SmtpError.SERVER_ERROR ||
                           err is SmtpError.NOT_SUPPORTED) {
                    problem = ProblemType.SERVER_ERROR;
                }
                notify_report_problem(problem, err);
                cancellable.cancel();
            } catch (IOError.CANCELLED err) {
                // Nothing to do here — we're already cancelled. In
                // particular we don't want to report the cancelled
                // error as a problem since this is the normal
                // shutdown method.
            } catch (IOError err) {
                notify_report_problem(ProblemType.for_ioerror(err), err);
                cancellable.cancel();
            } catch (Error err) {
                notify_report_problem(ProblemType.GENERIC_ERROR, err);
                cancellable.cancel();
            }

            if (email_handled) {
                // send was good, reset nap length
                send_retry_seconds = MIN_SEND_RETRY_INTERVAL_SEC;
            } else {
                // send was bad, try sending again later
                if (id != null) {
                    this.outbox_queue.send(id);
                }

                if (!cancellable.is_cancelled()) {
                    debug("Outbox napping for %u seconds...", send_retry_seconds);
                    // Take a brief nap before continuing to allow
                    // connection problems to resolve.
                    yield Geary.Scheduler.sleep_async(send_retry_seconds);
                    send_retry_seconds = Geary.Numeric.uint_ceiling(
                        send_retry_seconds * 2,
                        MAX_SEND_RETRY_INTERVAL_SEC
                    );
                }
            }
        }

        this.queue_cancellable = null;
        debug("Exiting outbox postie");
    }

    /**
     * Stops delivery of messages in the queue.
     */
    private void stop_postie() {
        debug("Stopping outbox postie");
        Cancellable? old_cancellable = this.queue_cancellable;
        if (old_cancellable != null) {
            old_cancellable.cancel();
        }
    }

    // Returns true if email was successfully processed, else false
    private async bool process_email(EmailIdentifier id, Cancellable cancellable)
        throws GLib.Error {
        Email? email = null;
        try {
            email = yield this.outbox.fetch_email_async(
                id, Email.Field.ALL, Folder.ListFlags.NONE, cancellable
            );
        } catch (EngineError.NOT_FOUND err) {
            debug("Queued email %s not found in outbox, ignoring: %s",
                  id.to_string(), err.message);
            return true;
        }

        bool mail_sent = email.email_flags.contains(EmailFlags.OUTBOX_SENT);
        if (!mail_sent) {
            // We immediately retry auth errors after the prompting
            // the user, but if they get it wrong enough times or
            // cancel we have no choice other than to stop the postie
            uint attempts = 0;
            while (!mail_sent && ++attempts <= Geary.Account.AUTH_ATTEMPTS_MAX) {
                RFC822.Message message = email.get_message();
                try {
                    debug("Outbox postie: Sending \"%s\" (ID:%s)...",
                          message_subject(message), email.id.to_string());
                    yield send_email(message, cancellable);
                    mail_sent = true;
                } catch (Error send_err) {
                    debug("Outbox postie send error: %s", send_err.message);
                    if (send_err is SmtpError.AUTHENTICATION_FAILED) {
                        if (attempts == Geary.Account.AUTH_ATTEMPTS_MAX) {
                            throw send_err;
                        }

                        // At this point we may already have a
                        // password in memory -- but it's incorrect.
                        if (!yield this.account.prompt_smtp_credentials(cancellable)) {
                            // The user cancelled and hence they don't
                            // want to be prompted again, so bail out.
                            throw send_err;
                        }
                    } else {
                        // not much else we can do - just bail out
                        throw send_err;
                    }
                }
            }

            // Mark as sent, so if there's a problem pushing up to
            // Sent, we don't retry sending. Don't pass the
            // cancellable here - if it's been sent we want to try to
            // update the sent flag anyway
            if (mail_sent) {
                debug("Outbox postie: Marking %s as sent", email.id.to_string());
                Geary.EmailFlags flags = new Geary.EmailFlags();
                flags.add(Geary.EmailFlags.OUTBOX_SENT);
                yield this.outbox.mark_email_async(
                    Collection.single(email.id), flags, null, null
                );
            }

            if (!mail_sent || cancellable.is_cancelled()) {
                // try again later
                return false;
            }
        }

        // If we get to this point, the message has either been just
        // sent, or previously sent but not saved. So now try flagging
        // as such and saving it.
        if (this.account.allow_save_sent_mail() &&
            this.account.save_sent_mail) {
            try {
                debug("Outbox postie: Saving %s to sent mail", email.id.to_string());
                yield save_sent_mail_async(email, cancellable);
            } catch (Error err) {
                debug("Outbox postie: Error saving sent mail: %s", err.message);
                notify_report_problem(ProblemType.SEND_EMAIL_SAVE_FAILED, err);
                return false;
            }
        }

        // Again, don't observe the cancellable here - if it's been
        // send and saved we want to try to remove it anyway.
        debug("Outbox postie: Deleting row %s", email.id.to_string());
        yield this.outbox.remove_email_async(Collection.single(email.id), null);

        return true;
    }

    private async void send_email(Geary.RFC822.Message rfc822, Cancellable? cancellable)
        throws Error {
        Smtp.ClientSession smtp = new Geary.Smtp.ClientSession(this.endpoint);

        sending_monitor.notify_start();

        Error? smtp_err = null;
        try {
            yield smtp.login_async(
                this.account.get_smtp_credentials(), cancellable
            );
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
                        if (this.account.has_email_address(from)) {
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

        email_sent(rfc822);
    }

    private async void save_sent_mail_async(Geary.Email email,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        Geary.FolderSupport.Create? create = (
            yield this.owner.get_required_special_folder_async(
                Geary.SpecialFolderType.SENT, cancellable
            )
        ) as Geary.FolderSupport.Create;
        if (create == null) {
            throw new EngineError.UNSUPPORTED(
                "Save sent mail enabled, but no writable sent mail folder"
            );
        }

        RFC822.Message message = email.get_message();
        bool open = false;
        try {
            yield create.open_async(Geary.Folder.OpenFlags.NO_DELAY, cancellable);
            open = true;
            yield create.create_email_async(message, null, null, null, cancellable);
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

    private void notify_report_problem(ProblemType problem, Error? err) {
        report_problem(
            new ServiceProblemReport(problem, this.account, this.service, err)
        );
    }

    private void on_reachable_changed() {
        if (this.endpoint.connectivity.is_reachable.is_certain()) {
            start_postie.begin();
        } else {
            stop_postie();
        }
    }

    private void on_connectivity_error(Error error) {
        stop_postie();
        notify_report_problem(ProblemType.CONNECTION_ERROR, error);
    }

}
