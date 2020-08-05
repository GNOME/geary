/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.Folder : Geary.Folder,
    ValaUnit.TestAssertions,
    ValaUnit.MockObject {


    public override Geary.Account account {
        get { return this._account; }
    }

    public override Geary.FolderProperties properties {
        get { return this._properties; }
    }

    public override Geary.FolderPath path {
        get { return this._path; }
    }

    public override Geary.Folder.SpecialUse used_as {
        get { return this._used_as; }
    }

    public override Geary.ProgressMonitor opening_monitor {
        get { return this._opening_monitor; }
    }

    protected Gee.Queue<ValaUnit.ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
    }


    private Geary.Account _account;
    private Geary.FolderProperties _properties;
    private Geary.FolderPath _path;
    private Geary.Folder.SpecialUse _used_as;
    private Geary.ProgressMonitor _opening_monitor;


    public Folder(Geary.Account? account,
                  Geary.FolderProperties? properties,
                  Geary.FolderPath? path,
                  Geary.Folder.SpecialUse used_as,
                  Geary.ProgressMonitor? monitor) {
        this._account = account;
        this._properties = properties ?? new FolderPoperties();
        this._path = path;
        this._used_as = used_as;
        this._opening_monitor = monitor;
    }

    public override Geary.Folder.OpenState get_open_state() {
        return Geary.Folder.OpenState.CLOSED;
    }

    public override async bool open_async(Geary.Folder.OpenFlags open_flags,
                                          GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield boolean_call_async(
            "open_async",
            { int_arg(open_flags), cancellable },
            false
        );
    }

    public override async bool close_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield boolean_call_async(
            "close_async", { cancellable }, false
        );
    }

    public override async void wait_for_close_async(GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public override async void synchronise_remote(GLib.Cancellable? cancellable)
        throws GLib.Error {
        void_call("synchronise_remote", { cancellable });
    }

    public override async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        return yield object_call_async<Gee.Collection<Geary.EmailIdentifier>>(
            "contains_identifiers",
            {ids, cancellable},
            new Gee.LinkedList<Geary.EmailIdentifier>()
        );
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_id_async(Geary.EmailIdentifier? initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Geary.Folder.ListFlags flags,
                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield object_call_async<Gee.List<Geary.Email>?>(
            "list_email_by_id_async",
            {initial_id, int_arg(count), box_arg(required_fields), box_arg(flags), cancellable},
            null
        );
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Geary.Email.Field required_fields,
                                      Geary.Folder.ListFlags flags,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield object_call_async<Gee.List<Geary.Email>?>(
            "list_email_by_sparse_id_async",
            {ids, box_arg(required_fields), box_arg(flags), cancellable},
            null
        );
    }

    public override async Geary.Email
        fetch_email_async(Geary.EmailIdentifier email_id,
                          Geary.Email.Field required_fields,
                          Geary.Folder.ListFlags flags,
                          GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public override void set_used_as_custom(bool enabled)
        throws Geary.EngineError.UNSUPPORTED {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

}
