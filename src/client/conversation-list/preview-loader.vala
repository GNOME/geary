/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Loads message body previews for conversation list items asynchronously.
 */
public class PreviewLoader : Geary.BaseObject {


    /** Email fields required to load message previews. */
    public const Geary.Email.Field REQUIRED_FIELDS =
        ConversationListModel.REQUIRED_FIELDS |
        Geary.Email.Field.PREVIEW |
        // XXX Remove ALL and NONE below when PREVIEW has been
        // fixed. See Bug 714317.
        Geary.Email.Field.ALL | Geary.Email.Field.NONE;


    /** Progress monitor for loading previews from the database. */
    public Geary.ProgressMonitor progress {
        get;
        private set;
        default = new Geary.ReentrantProgressMonitor(
            Geary.ProgressType.ACTIVITY
        );
    }


    private class LoadSet {

        public Gee.Map<Geary.EmailIdentifier,Geary.Email?> to_load =
            new Gee.HashMap<Geary.EmailIdentifier,Geary.Email?>();
        public Geary.Nonblocking.Semaphore loaded =
            new Geary.Nonblocking.Semaphore();

    }



    private LoadSet next_set = new LoadSet();
    private Geary.App.EmailStore email_store;
    private Geary.TimeoutManager load_timer;
    private Cancellable cancellable;
    private bool loading_local_only = true;


    public PreviewLoader(Geary.App.EmailStore email_store, Cancellable cancellable) {
        this.email_store = email_store;
        this.cancellable = cancellable;

        this.load_timer = new Geary.TimeoutManager.seconds(
            1, () => { this.do_load.begin(); }
        );
    }

    ~PreviewLoader() {
        this.load_timer.reset();
    }

    public void load_remote() {
        this.loading_local_only = false;
        this.do_load.begin();
    }

    public async Geary.Email request(Geary.Email target, Cancellable load_cancellable) {
        LoadSet this_set = this.next_set;
        this_set.to_load.set(target.id, null);
        this.load_timer.start();
        try {
            yield this_set.loaded.wait_async(load_cancellable);
        } catch (Error err) {
            // Oh well
        }
        return this_set.to_load.get(target.id);
    }

    private async void do_load() {
        LoadSet this_set = this.next_set;
        this.next_set = new LoadSet();
        this.load_timer.reset();

        if (!this_set.to_load.is_empty) {
            Geary.Folder.ListFlags flags = (this.loading_local_only)
                ? Geary.Folder.ListFlags.LOCAL_ONLY
                : Geary.Folder.ListFlags.NONE;

            Gee.Collection<Geary.Email>? emails = null;
            try {
                emails = yield email_store.list_email_by_sparse_id_async(
                    this_set.to_load.keys,
                    REQUIRED_FIELDS,
                    flags,
                    this.cancellable
                );
            } catch (Error err) {
                // Ignore NOT_FOUND, as that's entirely possible when
                // waiting for the remote to open
                if (!(err is Geary.EngineError.NOT_FOUND))
                    debug("Unable to fetch preview: %s", err.message);
            }

            if (emails != null) {
                foreach (Geary.Email email in emails) {
                    this_set.to_load.set(email.id, email);
                }
            }

            this_set.loaded.blind_notify();
            this.progress.notify_finish();
        }
    }

}
