/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockFolder : Folder, MockObject {


    public override Account account {
        get { return this._account; }
    }

    public override FolderProperties properties {
        get { return this._properties; }
    }

    public override FolderPath path {
        get { return this._path; }
    }

    public override Folder.SpecialUse used_as {
        get { return this._used_as; }
    }

    public override ProgressMonitor opening_monitor {
        get { return this._opening_monitor; }
    }

    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }


    private Account _account;
    private FolderProperties _properties;
    private FolderPath _path;
    private Folder.SpecialUse _used_as;
    private ProgressMonitor _opening_monitor;


    public MockFolder(Account? account,
                      FolderProperties? properties,
                      FolderPath? path,
                      Folder.SpecialUse used_as,
                      ProgressMonitor? monitor) {
        this._account = account;
        this._properties = properties ?? new MockFolderPoperties();
        this._path = path;
        this._used_as = used_as;
        this._opening_monitor = monitor;
    }

    public override Folder.OpenState get_open_state() {
        return OpenState.CLOSED;
    }

    public override async bool open_async(Folder.OpenFlags open_flags,
                                 Cancellable? cancellable = null)
        throws GLib.Error {
        return yield boolean_call_async(
            "open_async",
            { int_arg(open_flags), cancellable },
            false
        );
    }

    public override async bool close_async(Cancellable? cancellable = null)
        throws GLib.Error {
        return yield boolean_call_async(
            "close_async", { cancellable }, false
        );
    }

    public override async void wait_for_close_async(Cancellable? cancellable = null)
    throws GLib.Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void synchronise_remote(GLib.Cancellable? cancellable)
        throws GLib.Error {
        void_call("synchronise_remote", { cancellable });
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_id_async(Geary.EmailIdentifier? initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Folder.ListFlags flags,
                               Cancellable? cancellable = null)
        throws GLib.Error {
        return yield object_call_async<Gee.List<Email>?>(
            "list_email_by_id_async",
            {initial_id, int_arg(count), box_arg(required_fields), box_arg(flags), cancellable},
            null
        );
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Geary.Email.Field required_fields,
                                      Folder.ListFlags flags,
                                      Cancellable? cancellable = null)
        throws GLib.Error {
        return yield object_call_async<Gee.List<Email>?>(
            "list_email_by_sparse_id_async",
            {ids, box_arg(required_fields), box_arg(flags), cancellable},
            null
        );
    }

    public override async Geary.Email
        fetch_email_async(Geary.EmailIdentifier email_id,
                          Geary.Email.Field required_fields,
                          Folder.ListFlags flags,
                          Cancellable? cancellable = null)
    throws GLib.Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override void set_used_as_custom(bool enabled)
        throws EngineError.UNSUPPORTED {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

}
