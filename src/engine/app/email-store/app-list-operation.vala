/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ListOperation : Geary.App.AsyncFolderOperation {

    public override Type folder_type { get { return typeof(Folder); } }

    public Gee.Collection<Geary.Email> results { get; private set; }
    public Email.Field required_fields { get; private set; }
    public Folder.GetFlags flags { get; private set; }


    public ListOperation(Email.Field required_fields, Folder.GetFlags flags) {
        this.results = new Gee.HashSet<Geary.Email>();
        this.required_fields = required_fields;
        this.flags = flags;
    }

    public override async Gee.Collection<Geary.EmailIdentifier> execute_async(
        Folder folder,
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable
    ) throws GLib.Error {
        this.results = yield folder.get_multiple_email_by_id(
            ids, required_fields, this.flags, cancellable
        );
        return ids;
    }
}
