/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.FetchOperation : Geary.App.AsyncFolderOperation {

    public override Type folder_type { get { return typeof(Geary.Folder); } }

    public Email? result { get; private set; default = null; }
    public Email.Field required_fields { get; private set; }
    public Folder.GetFlags flags { get; private set; }


    public FetchOperation(Email.Field required_fields, Folder.GetFlags flags) {
        this.required_fields = required_fields;
        this.flags = flags;
    }

    public override async Gee.Collection<EmailIdentifier> execute_async(
        Folder folder,
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable
    ) throws GLib.Error {
        var id = Collection.first(ids);
        this.result = yield folder.get_email_by_id(
            id, required_fields, this.flags, cancellable
        );
        return iterate<EmailIdentifier>(id).to_array_list();
    }
}
