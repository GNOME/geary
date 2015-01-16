/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Manage saving, replacing, and deleting the various versions of a draft message while the user is
 * editing it.
 *
 * Each composer should create a single DraftManager object for the lifetime of the compose
 * session.  The DraftManager interface offers "fire-and-forget" nonblocking (but not
 * asynchronous) methods for the composer to schedule remote operations without worrying about
 * synchronization, operation ordering, error-handling, and so forth.
 *
 * If successive drafts are submitted for storage, drafts waiting in the queue (i.e. not yet sent
 * to the server) are dropped without further consideration.  This prevents needless I/O with the
 * server saving drafts that are only to be replaced by later versions.
 *
 * Important: This object should be used ''per'' composed email and not to manage multiple emails
 * being composed to the same {@link Account}.  DraftManager's internal state is solely for managing
 * the lifecycle of a single email being composed by the user.
 *
 * The only async calls for DraftManager is {@link open_async} and {@link close_async}, which give
 * it a chance to initialize and tear-down in an orderly manner.
 */

public class Geary.App.DraftManager : BaseObject {
    public const string PROP_IS_OPEN = "is-open";
    public const string PROP_DRAFT_STATE = "draft-state";
    public const string PROP_CURRENT_DRAFT_ID = "current-draft-id";
    public const string PROP_VERSIONS_SAVED = "versions-saved";
    public const string PROP_VERSIONS_DROPPED = "versions-dropped";
    public const string PROP_DISCARD_ON_CLOSE = "discard-on-close";
    
    /**
     * Current saved state of the draft.
     */
    public enum DraftState {
        /**
         * Indicates not stored on the remote server (either not uploaded or discarded).
         */
        NOT_STORED,
        /**
         * A save (upload) is in process.
         */
        STORING,
        /**
         * Draft is stored on the remote.
         */
        STORED,
        /**
         * A non-fatal error occurred attempting to store the draft.
         *
         * @see draft_failed
         */
        ERROR
    }
    
    private enum OperationType {
        PUSH,
        CLOSE
    }
    
    private class Operation : BaseObject {
        public OperationType op_type;
        public RFC822.Message? draft;
        public EmailFlags? flags;
        public DateTime? date_received;
        public Nonblocking.Semaphore? semaphore;
        
        public Operation(OperationType op_type, RFC822.Message? draft, EmailFlags? flags,
            DateTime? date_received, Nonblocking.Semaphore? semaphore) {
            this.op_type = op_type;
            this.draft = draft;
            this.flags = flags;
            this.date_received = date_received;
            this.semaphore = semaphore;
        }
    }
    
    /**
     * Indicates the {@link DraftsManager} is open and ready for service.
     *
     * Although this property can be monitored, the object is considered "open" when
     * {@link open_async} completes, not when this property changes to true.
     */
    public bool is_open { get; private set; default = false; }
    
    /**
     * The current saved state of the draft.
     */
    public DraftState draft_state { get; private set; default = DraftState.NOT_STORED; }
    
    /**
     * The {@link Geary.EmailIdentifier} of the last saved draft.
     */
    public Geary.EmailIdentifier? current_draft_id { get; private set; default = null; }
    
    /**
     * The version number of the most recently saved draft.
     *
     * Even if an initial draft is supplied (with {@link open_async}, this always starts at zero.
     * It merely represents the number of times a draft was successfully saved.
     *
     * A {@link discard} operation will reset this counter to zero.
     */
    public int versions_saved { get; private set; default = 0; }
    
    /**
     * The number of drafts dropped as new ones are added to the queue.
     *
     * @see dropped
     */
    public int versions_dropped { get; private set; default = 0; }
    
    /**
     * When set, the draft will be discarded when {@link close_async} is called.
     *
     * In addition, when set all future {@link update}s will result in the draft being dropped.
     */
    public bool discard_on_close { get; set; default = false; }
    
    private Account account;
    private Folder? drafts_folder = null;
    private FolderSupport.Create? create_support = null;
    private FolderSupport.Remove? remove_support = null;
    private Nonblocking.Mailbox<Operation?> mailbox = new Nonblocking.Mailbox<Operation?>();
    private bool was_opened = false;
    private Error? fatal_err = null;
    
    /**
     * Fired when a draft is successfully saved.
     */
    public signal void stored(Geary.RFC822.Message draft);
    
    /**
     * Fired when a draft is discarded.
     */
    public signal void discarded();
    
    /**
     * Fired when a draft is dropped.
     *
     * This occurs when a draft is scheduled for {@link update} while another draft is queued
     * to be pushed to the server.  The queued draft is dropped in favor of the new one.
     */
    public signal void dropped(Geary.RFC822.Message draft);
    
    /**
     * Fired when unable to save a draft but the {@link DraftManager} remains open.
     *
     * Due to unpredictability of errors being reported, it's possible this signal will fire after
     * {@link fatal}.  It should not be assumed this signal firing means DraftManager is still
     * operational, but if fatal fires, it definitely is not operational.
     */
    public virtual signal void draft_failed(Geary.RFC822.Message draft, Error err) {
        debug("%s: Unable to create draft: %s", to_string(), err.message);
    }
    
    /**
     * Fired if an unrecoverable error occurs while processing drafts.
     *
     * The {@link DraftManager} will be unable to process future drafts.
     */
    public virtual signal void fatal(Error err) {
        fatal_err = err;
        
        debug("%s: Irrecoverable failure: %s", to_string(), err.message);
    }
    
    public DraftManager(Geary.Account account) {
        this.account = account;
    }
    
    protected virtual void notify_stored(Geary.RFC822.Message draft) {
        versions_saved++;
        stored(draft);
    }
    
    protected virtual void notify_discarded() {
        versions_saved = 0;
        discarded();
    }
    
    /**
     * Open the {@link DraftManager} and prepare it for handling composed messages.
     *
     * An initial draft EmailIdentifier may be supplied indicating the starting draft (when editing,
     * not creating a new draft).  No checking is performed to ensure this EmailIdentifier is valid
     * for the drafts folder, nor is it downloaded by DraftManager.  In essence, this email is
     * deleted by the manager when the first {@link update} occurs or the draft is
     * {@link discard}ed.
     *
     * If an initial_draft is supplied, {@link draft_state} will be set to {@link DraftState.STORED}.
     *
     * Other method calls should not be invoked until this completes successfully.
     *
     * @see is_open
     */
    public async void open_async(Geary.EmailIdentifier? initial_draft_id, Cancellable? cancellable = null)
        throws Error {
        if (is_open)
            throw new EngineError.ALREADY_OPEN("%s is already open", to_string());
        else if (was_opened)
            throw new EngineError.UNSUPPORTED("%s cannot be re-opened", to_string());
        
        was_opened = true;
        
        current_draft_id = initial_draft_id;
        if (current_draft_id != null)
            draft_state = DraftState.STORED;
        
        drafts_folder = account.get_special_folder(SpecialFolderType.DRAFTS);
        if (drafts_folder == null)
            throw new EngineError.NOT_FOUND("%s: No drafts folder found", to_string());
        
        // if drafts folder doesn't support create and remove, call it quits
        create_support = drafts_folder as Geary.FolderSupport.Create;
        remove_support = drafts_folder as Geary.FolderSupport.Remove;
        if (create_support == null || remove_support == null) {
            throw new EngineError.UNSUPPORTED("%s: Drafts folder %s does not support create and remove",
                to_string(), drafts_folder.to_string());
        }
        
        drafts_folder.closed.connect(on_folder_closed);
        
        yield drafts_folder.open_async(Folder.OpenFlags.NONE, cancellable);
        
        // if drafts folder doesn't return the identifier of newly created emails, then this object
        // can't do it's work ... wait until open to check for this, to be absolutely sure
        if (drafts_folder.properties.create_never_returns_id) {
            try {
                yield drafts_folder.close_async();
            } catch (Error err) {
                // ignore
            }
            
            throw new EngineError.UNSUPPORTED("%s: Drafts folder %s does not return created mail ID",
                to_string(), drafts_folder.to_string());
        }
        
        // start the operation message loop, which ensures commands are handled in orderly fashion
        operation_loop_async.begin();
        
        // done
        is_open = true;
    }
    
    private void on_folder_closed(Folder.CloseReason reason) {
        if (reason == Folder.CloseReason.FOLDER_CLOSED) {
            fatal(new EngineError.SERVER_UNAVAILABLE("%s: Unexpected drafts folder closed (%s)",
                to_string(), reason.to_string()));
        }
    }
    
    /**
     * Flush pending operations and close the {@link DraftsManager}.
     *
     * Once closed, the object cannot be opened again.  Create a new object in that case.
     *
     * @see open_async
     * @see is_open
     */
    public async void close_async(Cancellable? cancellable = null) throws Error {
        if (!is_open || drafts_folder == null)
            return;
        
        // prevent further operations
        is_open = false;
        
        // don't flush a CLOSE down the pipe if failed, the operation loop is closed for business
        if (fatal_err == null) {
            // if discarding on close, do so now
            if (discard_on_close) {
                // don't use discard(), which checks if open, but submit_push() directly,
                // which doesn't
                submit_push(null, null, null);
            }
            
            // flush pending I/O
            Nonblocking.Semaphore semaphore = new Nonblocking.Semaphore(cancellable);
            mailbox.send(new Operation(OperationType.CLOSE, null, null, null, semaphore));
            
            // wait for close to complete
            try {
                yield semaphore.wait_async(cancellable);
            } catch (Error err) {
                if (err is IOError.CANCELLED)
                    throw err;
                
                // fall through
            }
        }
        
        // Disconnect before closing, as signal handler is for unexpected closes
        drafts_folder.closed.disconnect(on_folder_closed);
        
        try {
            yield drafts_folder.close_async(cancellable);
        } finally {
            drafts_folder = null;
            create_support = null;
            remove_support = null;
        }
    }
    
    private void check_open() throws EngineError {
        if (!is_open)
            throw new EngineError.OPEN_REQUIRED("%s is not open", to_string());
    }
    
    /**
     * Save draft on the server, potentially replacing (deleting) an already-existing version.
     *
     * See {@link FolderSupport.Create.create_email_async} for more information on the flags and
     * date_received arguments.
     *
     * @returns A {@link Semaphore} that is notified when the operation completes (with or without
     * error)
     */
    public Geary.Nonblocking.Semaphore? update(Geary.RFC822.Message draft, Geary.EmailFlags? flags,
        DateTime? date_received) throws Error {
        check_open();
        
        return submit_push(draft, flags, date_received);
    }
    
    /**
     * Delete all versions of the composed email from the server.
     *
     * This is appropriate both for the user cancelling (discarding) a composed message or if the
     * user sends it.
     *
     * Note: Replaced drafts are deleted, but on some services (i.e. Gmail) those deleted messages
     * are actually moved to the Trash.  This call does not currently solve that problem.
     *
     * @returns A {@link Semaphore} that is notified when the operation completes (with or without
     * error)
     */
    public Geary.Nonblocking.Semaphore? discard() throws Error {
        check_open();
        
        return submit_push(null, null, null);
    }
    
    // Note that this call doesn't check_open(), important when used within close_async()
    private Nonblocking.Semaphore? submit_push(RFC822.Message? draft, EmailFlags? flags,
        DateTime? date_received) {
        // no drafts are pushed when discarding on close
        if (draft != null && discard_on_close) {
            versions_dropped++;
            dropped(draft);
            
            return null;
        }
        
        // clear out pending pushes (which can be updates or discards)
        mailbox.revoke_matching((op) => {
            // count and notify of dropped drafts
            if (op.op_type == OperationType.PUSH && op.draft != null) {
                versions_dropped++;
                dropped(op.draft);
            }
            
            return op.op_type == OperationType.PUSH;
        });
        
        Nonblocking.Semaphore semaphore = new Nonblocking.Semaphore();
        
        // schedule this draft for update (if null, it's a discard)
        mailbox.send(new Operation(OperationType.PUSH, draft, flags, date_received, semaphore));
        
        return semaphore;
    }
    
    private async void operation_loop_async() {
        for (;;) {
            // if a fatal error occurred (it can happen outside the loop), shutdown without
            // reporting it again
            if (fatal_err != null)
                break;
            
            Operation op;
            try {
                op = yield mailbox.recv_async(null);
            } catch (Error err) {
                fatal(err);
                
                break;
            }
            
            bool continue_loop = yield operation_loop_iteration_async(op);
            
            // fire semaphore, if present
            if (op.semaphore != null)
                op.semaphore.blind_notify();
            
            if (!continue_loop)
                break;
        }
    }
    
    // Returns false if time to exit.
    private async bool operation_loop_iteration_async(Operation op) {
        // watch for CLOSE
        if (op.op_type == OperationType.CLOSE)
            return false;
        
        // make sure there's a folder to work with
        if (drafts_folder == null || drafts_folder.get_open_state() == Folder.OpenState.CLOSED) {
            fatal(new EngineError.SERVER_UNAVAILABLE("%s: premature drafts folder close", to_string()));
            
            return false;
        }
        
        // at this point, only operation left is PUSH
        assert(op.op_type == OperationType.PUSH);
        
        draft_state = DraftState.STORING;
        
        // delete old draft for all PUSHes: best effort ... since create_email_async() will handle
        // replacement in a transactional-kinda-way, only outright delete if not using create
        if (current_draft_id != null && op.draft == null) {
            bool success = false;
            try {
                yield remove_support.remove_single_email_async(current_draft_id);
                success = true;
            } catch (Error err) {
                debug("%s: Unable to remove existing draft %s: %s", to_string(), current_draft_id.to_string(),
                    err.message);
            }
            
            // always clear draft id (assuming that retrying a failed remove is unnecessary), but
            // only signal the discard if it actually was removed
            current_draft_id = null;
            if (success)
                notify_discarded();
        }
        
        // if draft supplied, save it
        if (op.draft != null) {
            try {
                current_draft_id = yield create_support.create_email_async(op.draft, op.flags,
                    op.date_received, current_draft_id, null);
                
                draft_state = DraftState.STORED;
                notify_stored(op.draft);
            } catch (Error err) {
                draft_state = DraftState.ERROR;
                
                // notify subscribers
                draft_failed(op.draft, err);
            }
        } else {
            draft_state = DraftState.NOT_STORED;
        }
        
        return true;
    }
    
    public string to_string() {
        return "%s DraftManager".printf(account.to_string());
    }
}

