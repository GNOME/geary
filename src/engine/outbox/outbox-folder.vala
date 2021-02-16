/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A folder for storing outgoing mail.
 */
public class Geary.Outbox.Folder : BaseObject,
    Logging.Source,
    Geary.Folder,
    FolderSupport.Create,
    FolderSupport.Mark,
    FolderSupport.Remove {


    /** The canonical name of the outbox folder. */
    public const string MAGIC_BASENAME = "$GearyOutbox$";


    private class OutboxRow {
        public int64 id;
        public int position;
        public int64 ordering;
        public bool sent;
        public Memory.Buffer? message;
        public EmailIdentifier outbox_id;

        public OutboxRow(int64 id, int position, int64 ordering, bool sent, Memory.Buffer? message) {
            assert(position >= 1);

            this.id = id;
            this.position = position;
            this.ordering = ordering;
            this.sent = sent;
            this.message = message;

            outbox_id = new EmailIdentifier(id, ordering);
        }
    }


    /** {@inheritDoc} */
    public override Account account {
        get { return this._account; }
    }

    /**
     * Returns the path to this folder.
     *
     * This is always the child of the root given to the constructor,
     * with the name given by {@link MAGIC_BASENAME}.
     */
    public override Geary.Folder.Path path {
        get { return this._path; }
    }
    private Geary.Folder.Path _path;

    /** {@inheritDoc} */
    public int email_total {
        get { return this._email_total; }
    }
    private int _email_total = 0;

    /** {@inheritDoc} */
    public int email_unread {
        get { return 0; }
    }

    /**
     * Returns the type of this folder.
     *
     * This is always {@link Folder.SpecialUse.OUTBOX}
     */
    public override Geary.Folder.SpecialUse used_as {
        get {
            return OUTBOX;
        }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent {
        get { return this.account; }
    }

    private weak Account _account;
    private Db.Database db = null;
    private int64 next_ordering = 0;


    internal Folder(Account account,
                    Geary.Folder.Root root,
                    Db.Database db) {
        this._account = account;
        this._path = root.get_child(MAGIC_BASENAME, Trillian.TRUE);
        this.db = db;
    }

    public virtual async Geary.EmailIdentifier?
        create_email_async(RFC822.Message rfc822,
                           Geary.EmailFlags? flags,
                           GLib.DateTime? date_received,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        OutboxRow? row = null;
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            int64 ordering = do_get_next_ordering(cx, cancellable);

            // save in database ready for SMTP, but without dot-stuffing
            Db.Statement stmt = cx.prepare(
                "INSERT INTO SmtpOutboxTable (message, ordering) VALUES (?, ?)");
            stmt.bind_string_buffer(0, rfc822.get_rfc822_buffer());
            stmt.bind_int64(1, ordering);

            int64 new_id = stmt.exec_insert(cancellable);
            int position = do_get_position_by_ordering(cx, ordering, cancellable);

            row = new OutboxRow(new_id, position, ordering, false, null);

            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        this._email_total++;
        notify_property("email-total");

        var list = Geary.Collection.single(row.outbox_id);
        this.account.email_added(list, this);
        email_inserted(list);

        return row.outbox_id;
    }

    public virtual async void
        mark_email_async(Gee.Collection<Geary.EmailIdentifier> to_mark,
                         EmailFlags? flags_to_add,
                         EmailFlags? flags_to_remove,
                         GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Gee.Map<Geary.EmailIdentifier,EmailFlags> changed =
            new Gee.HashMap<Geary.EmailIdentifier,EmailFlags>();

        foreach (Geary.EmailIdentifier id in to_mark) {
            EmailIdentifier? outbox_id = id as EmailIdentifier;
            if (outbox_id != null) {
                yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
                        do_mark_email_as_sent(cx, outbox_id, cancellable);
                        return Db.TransactionOutcome.COMMIT;
                    }, cancellable
                );
                changed.set(id, flags_to_add);
            }
        }

        email_flags_changed(changed);
    }

    public virtual async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        var removed = new Gee.ArrayList<Geary.EmailIdentifier>();
        yield db.exec_transaction_async(Db.TransactionType.WR, (cx) => {
            foreach (Geary.EmailIdentifier id in email_ids) {
                // ignore anything not belonging to the outbox, but also don't report it as removed
                // either
                EmailIdentifier? outbox_id = id as EmailIdentifier;
                if (outbox_id == null)
                    continue;

                // Even though we discard the new value here, this check must
                // occur before any insert/delete on the table, to ensure we
                // never reuse an ordering value while Geary is running.
                do_get_next_ordering(cx, cancellable);

                if (do_remove_email(cx, outbox_id, cancellable)) {
                    removed.add(outbox_id);
                }
            }
            return Db.TransactionOutcome.COMMIT;
        }, cancellable);

        if (!removed.is_empty) {
            this._email_total -= removed.size;
            notify_property("email-total");
            email_removed(removed);
        }
    }

    /** {@inheritDoc} */
    public async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        var contains = new Gee.HashSet<Geary.EmailIdentifier>();
        yield db.exec_transaction_async(
            RO,
            (cx, cancellable) => {
                foreach (Geary.EmailIdentifier id in ids) {
                    var outbox_id = id as EmailIdentifier;
                    if (outbox_id != null) {
                        var row = do_fetch_row_by_ordering(
                            cx, outbox_id.ordering, cancellable
                        );
                        if (row != null) {
                            contains.add(id);
                        }
                    }
                }
                return DONE;
            },
            cancellable
        );
        return contains;
    }

    /** {@inheritDoc} */
    public async Email get_email_by_id(Geary.EmailIdentifier id,
                                       Email.Field required_fields,
                                       GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        EmailIdentifier? outbox_id = id as EmailIdentifier;
        if (outbox_id == null)
            throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());

        OutboxRow? row = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            row = do_fetch_row_by_ordering(cx, outbox_id.ordering, cancellable);

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        if (row == null)
            throw new EngineError.NOT_FOUND("No message with ID %s in outbox", id.to_string());

        return row_to_email(row);
    }

    public async Gee.List<Email>?
        list_email_by_id_async(Geary.EmailIdentifier? _initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Geary.Folder.ListFlags flags,
                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        EmailIdentifier? initial_id = _initial_id as EmailIdentifier;
        if (_initial_id != null && initial_id == null) {
            throw new EngineError.BAD_PARAMETERS("EmailIdentifier %s not for Outbox",
                initial_id.to_string());
        }

        if (count <= 0)
            return null;

        bool list_all = (required_fields != Email.Field.NONE);

        string select = "id, ordering";
        if (list_all) {
            select = select + ", message, sent";
        }

        Gee.List<Geary.Email>? list = null;
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            string dir = flags.is_newest_to_oldest() ? "DESC" : "ASC";

            Db.Statement stmt;
            if (initial_id != null) {
                stmt = cx.prepare("""
                    SELECT %s
                    FROM SmtpOutboxTable
                    WHERE ordering >= ?
                    ORDER BY ordering %s
                    LIMIT ?
                """.printf(select ,dir));
                stmt.bind_int64(0,
                    flags.is_including_id() ? initial_id.ordering : initial_id.ordering + 1);
                stmt.bind_int(1, count);
            } else {
                stmt = cx.prepare("""
                    SELECT %s
                    FROM SmtpOutboxTable
                    ORDER BY ordering %s
                    LIMIT ?
                """.printf(select, dir));
                stmt.bind_int(0, count);
            }

            Db.Result results = stmt.exec(cancellable);
            if (results.finished)
                return Db.TransactionOutcome.DONE;

            list = new Gee.ArrayList<Geary.Email>();
            int position = -1;
            do {
                int64 ordering = results.int64_at(1);
                if (position == -1) {
                    position = do_get_position_by_ordering(
                        cx, ordering, cancellable
                    );
                    assert(position >= 1);
                }

                list.add(
                    row_to_email(
                        new OutboxRow(
                            results.rowid_at(0),
                            position,
                            ordering,
                            list_all ? results.bool_at(3) : false,
                            list_all ? results.string_buffer_at(2) : null
                        )
                    )
                );
                position += flags.is_newest_to_oldest() ? -1 : 1;
                assert(position >= 1);
            } while (results.next());

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return list;
    }

    public async Gee.List<Geary.Email>?
        list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Geary.Email.Field required_fields,
                                      Geary.Folder.ListFlags flags,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Gee.List<Geary.Email> list = new Gee.ArrayList<Geary.Email>();
        yield db.exec_transaction_async(Db.TransactionType.RO, (cx) => {
            foreach (Geary.EmailIdentifier id in ids) {
                EmailIdentifier? outbox_id = id as EmailIdentifier;
                if (outbox_id == null)
                    throw new EngineError.BAD_PARAMETERS("%s is not outbox EmailIdentifier", id.to_string());

                OutboxRow? row = do_fetch_row_by_ordering(cx, outbox_id.ordering, cancellable);
                if (row == null)
                    continue;

                list.add(row_to_email(row));
            }

            return Db.TransactionOutcome.DONE;
        }, cancellable);

        return (list.size > 0) ? list : null;
    }

    /** {@inheritDoc} */
    public void set_used_as_custom(bool enabled)
        throws EngineError.UNSUPPORTED {
        throw new EngineError.UNSUPPORTED("Folder special use cannot be changed");
    }

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(this, this.path.to_string());
    }

    /** Initialises outbox state from the database */
    internal async void load(GLib.Cancellable cancellable) throws GLib.Error {
        yield this.db.exec_transaction_async(
            RO, (cx) => {
                Db.Statement stmt = cx.prepare("SELECT COUNT(*) FROM SmtpOutboxTable");
                Db.Result results = stmt.exec(cancellable);
                if (!results.finished) {
                    this._email_total = results.int_at(0);
                }
                return DONE;
            },
            cancellable
        );
    }

    // Utility for getting an email object back from an outbox row.
    private Geary.Email row_to_email(OutboxRow row) throws Error {
        Geary.Email? email = null;

        // If the row doesn't contain any message, just the id will do
        if (row.message == null) {
            email = new Email(row.outbox_id);
        } else {
            RFC822.Message message = new RFC822.Message.from_buffer(row.message);
            email = new Geary.Email.from_message(row.outbox_id, message);

            // TODO: Determine message's total size (header + body) to
            // store in Properties.
            email.set_email_properties(
                new EmailProperties(new DateTime.now_local(), -1)
            );
            Geary.EmailFlags flags = new Geary.EmailFlags();
            if (row.sent)
                flags.add(Geary.EmailFlags.OUTBOX_SENT);
            email.set_flags(flags);
        }

        return email;
    }

    //
    // Transaction helper methods
    //

    private int64 do_get_next_ordering(Db.Connection cx, Cancellable? cancellable) throws Error {
        lock (next_ordering) {
            if (next_ordering == 0) {
                Db.Statement stmt = cx.prepare("SELECT COALESCE(MAX(ordering), 0) + 1 FROM SmtpOutboxTable");

                Db.Result result = stmt.exec(cancellable);
                if (!result.finished)
                    next_ordering = result.int64_at(0);

                assert(next_ordering > 0);
            }

            return next_ordering++;
        }
    }

    private int do_get_position_by_ordering(Db.Connection cx, int64 ordering, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare(
            "SELECT COUNT(*), MAX(ordering) FROM SmtpOutboxTable WHERE ordering <= ? ORDER BY ordering ASC");
        stmt.bind_int64(0, ordering);

        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return -1;

        // without the MAX it's possible to overshoot, so the MAX(ordering) *must* match the argument
        if (results.int64_at(1) != ordering)
            return -1;

        return results.int_at(0) + 1;
    }

    private OutboxRow? do_fetch_row_by_ordering(Db.Connection cx, int64 ordering, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("""
            SELECT id, message, sent
            FROM SmtpOutboxTable
            WHERE ordering=?
        """);
        stmt.bind_int64(0, ordering);

        Db.Result results = stmt.exec(cancellable);
        if (results.finished)
            return null;

        int position = do_get_position_by_ordering(cx, ordering, cancellable);
        if (position < 1)
            return null;

        return new OutboxRow(results.rowid_at(0), position, ordering, results.bool_at(2),
            results.string_buffer_at(1));
    }

    private void do_mark_email_as_sent(Db.Connection cx,
                                       EmailIdentifier id,
                                       Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("UPDATE SmtpOutboxTable SET sent = 1 WHERE ordering = ?");
        stmt.bind_int64(0, id.ordering);

        stmt.exec(cancellable);
    }

    private bool do_remove_email(Db.Connection cx, EmailIdentifier id, Cancellable? cancellable)
        throws Error {
        Db.Statement stmt = cx.prepare("DELETE FROM SmtpOutboxTable WHERE ordering=?");
        stmt.bind_int64(0, id.ordering);

        return stmt.exec_get_modified(cancellable) > 0;
    }

}
