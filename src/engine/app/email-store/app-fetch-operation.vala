/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.FetchOperation : Geary.App.AsyncFolderOperation {
    public override Type folder_type { get { return typeof(Geary.Folder); } }

    public Geary.Email? result = null;
    public Geary.Email.Field required_fields;
    public Geary.Folder.ListFlags flags;

    public FetchOperation(Geary.Email.Field required_fields, Geary.Folder.ListFlags flags) {
        this.required_fields = required_fields;
        this.flags = flags;
    }

    public override async Gee.Collection<Geary.EmailIdentifier> execute_async(
        Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids,
        Cancellable? cancellable) throws Error {
        assert(result == null);
        Geary.EmailIdentifier? id = Collection.first(ids);
        assert(id != null);

        result = yield folder.fetch_email_async(
            id, required_fields, flags, cancellable);
        return Geary.iterate<Geary.EmailIdentifier>(id).to_array_list();
    }
}
