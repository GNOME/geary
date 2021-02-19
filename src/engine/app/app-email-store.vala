/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.App.EmailStore : BaseObject {
    public weak Geary.Account account { get; private set; }

    public EmailStore(Geary.Account account) {
        this.account = account;
    }

    /**
     * Return a map of EmailIdentifiers to the special Geary.FolderSupport
     * interfaces each one supports.  For example, if an EmailIdentifier comes
     * back mapped to typeof(Geary.FolderSupport.Mark), it can be marked via
     * mark_email_async().  If an EmailIdentifier doesn't appear in the
     * returned map, no operations are supported on it.
     */
    public async Gee.MultiMap<Geary.EmailIdentifier, Type>? get_supported_operations_async(
        Gee.Collection<Geary.EmailIdentifier> emails, Cancellable? cancellable = null) throws Error {
        Gee.MultiMap<Geary.EmailIdentifier, Folder.Path>? folders
            = yield account.get_containing_folders_async(emails, cancellable);
        if (folders == null)
            return null;

        Gee.HashSet<Type> all_support = new Gee.HashSet<Type>();
        all_support.add(typeof(Geary.FolderSupport.Archive));
        all_support.add(typeof(Geary.FolderSupport.Copy));
        all_support.add(typeof(Geary.FolderSupport.Create));
        all_support.add(typeof(Geary.FolderSupport.Mark));
        all_support.add(typeof(Geary.FolderSupport.Move));
        all_support.add(typeof(Geary.FolderSupport.Remove));

        Gee.HashMultiMap<Geary.EmailIdentifier, Type> map
            = new Gee.HashMultiMap<Geary.EmailIdentifier, Type>();
        foreach (Geary.EmailIdentifier email in folders.get_keys()) {
            Gee.HashSet<Type> support = new Gee.HashSet<Type>();

            foreach (Folder.Path path in folders.get(email)) {
                Geary.Folder folder;
                try {
                    folder = account.get_folder(path);
                } catch (Error e) {
                    debug("Error getting a folder from path %s: %s", path.to_string(), e.message);
                    continue;
                }

                foreach (Type type in all_support) {
                    if (folder.get_type().is_a(type))
                        support.add(type);
                }
                if (support.contains_all(all_support))
                    break;
            }

            Geary.Collection.multi_map_set_all<Geary.EmailIdentifier, Type>(map, email, support);
        }

        return (map.size > 0 ? map : null);
    }

    /**
     * Fetches any EmailIdentifier regardless of what folder it's in.
     */
    public async Email get_email_by_id(EmailIdentifier email_id,
                                       Email.Field required_fields = ALL,
                                       Folder.GetFlags flags = NONE,
                                       GLib.Cancellable? cancellable = null)
        throws GLib.Error {
            FetchOperation op = new Geary.App.FetchOperation(required_fields, flags);
        yield do_folder_operation_async(
            op, Collection.single(email_id), cancellable
        );

        if (op.result == null)
            throw new EngineError.NOT_FOUND("Couldn't fetch email ID %s", email_id.to_string());
        return op.result;
    }

    /**
     * Lists any set of EmailIdentifiers as if they were all in one folder.
     */
    public async Gee.Collection<Geary.Email> get_multiple_email_by_id(
        Gee.Collection<EmailIdentifier> emails,
        Email.Field required_fields = ALL,
        Folder.GetFlags flags = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var op = new Geary.App.ListOperation(required_fields, flags);
        yield do_folder_operation_async(op, emails, cancellable);
        return op.results;
    }

    /**
     * Marks any set of EmailIdentifiers as if they were all in one
     * Geary.FolderSupport.Mark folder.
     */
    public async void mark_email_async(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove,
        Cancellable? cancellable = null) throws Error {
        yield do_folder_operation_async(new Geary.App.MarkOperation(flags_to_add, flags_to_remove),
            emails, cancellable);
    }

    /**
     * Copies any set of EmailIdentifiers as if they were all in one
     * Geary.FolderSupport.Copy folder.
     */
    public async void copy_email_async(Gee.Collection<Geary.EmailIdentifier> emails,
        Folder.Path destination, Cancellable? cancellable = null) throws Error {
        yield do_folder_operation_async(new Geary.App.CopyOperation(destination),
            emails, cancellable);
    }

    private Folder.Path?
        next_folder_for_operation(AsyncFolderOperation operation,
                                  Gee.MultiMap<Folder.Path,EmailIdentifier> folders_to_ids)
        throws GLib.Error {
        Folder.Path? best = null;
        int best_count = 0;
        foreach (Folder.Path path in folders_to_ids.get_keys()) {
            Folder folder = this.account.get_folder(path);
            if (folder.get_type().is_a(operation.folder_type)) {
                int count = folders_to_ids.get(path).size;
                if (count > best_count) {
                    best_count = count;
                    best = path;
                }
            }
        }
        return best;
    }

    private async void do_folder_operation_async(AsyncFolderOperation operation,
        Gee.Collection<Geary.EmailIdentifier> emails, Cancellable? cancellable) throws Error {
        if (emails.size == 0)
            return;

        debug("EmailStore %s running %s on %d emails", account.to_string(),
            operation.get_type().name(), emails.size);

        Gee.MultiMap<Geary.EmailIdentifier, Folder.Path>? ids_to_folders
            = yield account.get_containing_folders_async(emails, cancellable);
        if (ids_to_folders == null)
            return;

        Gee.MultiMap<Folder.Path, Geary.EmailIdentifier> folders_to_ids
            = Geary.Collection.reverse_multi_map<Geary.EmailIdentifier, Folder.Path>(ids_to_folders);
        Folder.Path? path;
        while ((path = next_folder_for_operation(operation, folders_to_ids)) != null) {
            Geary.Folder folder = this.account.get_folder(path);
            Gee.Collection<Geary.EmailIdentifier> ids = folders_to_ids.get(path);
            assert(ids.size > 0);

            Gee.Collection<Geary.EmailIdentifier>? used_ids =
                yield operation.execute_async(folder, ids, cancellable);

            // We don't want to operate on any mails twice.
            if (used_ids != null) {
                foreach (Geary.EmailIdentifier id in used_ids.to_array()) {
                    foreach (Folder.Path p in ids_to_folders.get(id))
                        folders_to_ids.remove(p, id);
                }
            }
            // And we don't want to operate on the same folder twice.
            folders_to_ids.remove_all(path);
        }

        if (folders_to_ids.size > 0) {
            debug("Couldn't perform %s on some messages in %s", operation.get_type().name(),
                account.to_string());
        }
    }
}
