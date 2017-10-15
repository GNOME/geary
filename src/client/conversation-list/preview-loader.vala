/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Loads message body previews for conversation list items asynchronously.
 */
public class PreviewLoader : Geary.BaseObject {

    // XXX Remove ALL and NONE when PREVIEW has been fixed. See Bug 714317.
    private const Geary.Email.Field WITH_PREVIEW_FIELDS =
        Geary.Email.Field.ENVELOPE | Geary.Email.Field.FLAGS |
        Geary.Email.Field.PROPERTIES | Geary.Email.Field.PREVIEW |
        Geary.Email.Field.ALL | Geary.Email.Field.NONE;

    private Geary.App.EmailStore email_store;
    private Cancellable cancellable;
    private bool loading_local_only = true;


    public PreviewLoader(Geary.App.EmailStore email_store, Cancellable cancellable) {
        this.email_store = email_store;
        this.cancellable = cancellable;
    }

    public void load_remote() {
        this.loading_local_only = false;
    }

    public async string? load(Geary.Email target) {
        Gee.Collection<Geary.EmailIdentifier> pending = new Gee.HashSet<Geary.EmailIdentifier>();
        pending.add(target.id);

        Geary.Folder.ListFlags flags = (this.loading_local_only)
            ? Geary.Folder.ListFlags.LOCAL_ONLY
            : Geary.Folder.ListFlags.NONE;

        Gee.Collection<Geary.Email>? emails = null;
        try {
            emails = yield email_store.list_email_by_sparse_id_async(
                pending, ConversationListStore.WITH_PREVIEW_FIELDS, flags, this.cancellable
            );
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }

        Geary.Email? loaded = Geary.Collection.get_first(emails);
        string? preview = null;
        if (loaded != null) {
            preview = Geary.String.reduce_whitespace(loaded.get_preview_as_string());
        }
        return preview;
    }

}
