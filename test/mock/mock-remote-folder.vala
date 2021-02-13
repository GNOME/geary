/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.RemoteFolder : GLib.Object,
    Geary.Logging.Source,
    Geary.Folder,
    Geary.RemoteFolder,
    ValaUnit.TestAssertions,
    ValaUnit.MockObject {


    public Geary.Account account {
        get { return this._account; }
    }

    public Geary.FolderProperties properties {
        get { return this._properties; }
    }

    public Geary.FolderPath path {
        get { return this._path; }
    }

    public Geary.Folder.SpecialUse used_as {
        get { return this._used_as; }
    }

    public bool is_monitoring {
        get { return this._is_monitoring; }
    }
    private bool _is_monitoring = false;

    public bool is_fully_expanded {
        get { return this._is_fully_expanded; }
    }
    private bool _is_fully_expanded = false;

    public Geary.Logging.Source? logging_parent {
        get { return this.account; }
    }

    protected Gee.Queue<ValaUnit.ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
    }


    private Geary.Account _account;
    private Geary.FolderProperties _properties;
    private Geary.FolderPath _path;
    private Geary.Folder.SpecialUse _used_as;
    private Geary.ProgressMonitor _opening_monitor;


    public RemoteFolder(Geary.Account? account,
                        Geary.FolderProperties? properties,
                        Geary.FolderPath? path,
                        Geary.Folder.SpecialUse used_as,
                        Geary.ProgressMonitor? monitor,
                        bool is_monitoring,
                        bool is_fully_expanded) {
        this._account = account;
        this._properties = properties ?? new FolderPoperties();
        this._path = path;
        this._used_as = used_as;
        this._opening_monitor = monitor;
        this._is_monitoring = is_monitoring;
        this._is_fully_expanded = is_fully_expanded;
    }

    public async Gee.Collection<Geary.EmailIdentifier> contains_identifiers(
        Gee.Collection<Geary.EmailIdentifier> ids,
        GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        return yield object_call_async<Gee.Collection<Geary.EmailIdentifier>>(
            "contains_identifiers",
            {ids, cancellable},
            new Gee.LinkedList<Geary.EmailIdentifier>()
        );
    }

    public async Gee.List<Geary.Email>?
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

    public async Gee.List<Geary.Email>?
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

    public async Geary.Email
        fetch_email_async(Geary.EmailIdentifier email_id,
                          Geary.Email.Field required_fields,
                          Geary.Folder.ListFlags flags,
                          GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public void set_used_as_custom(bool enabled)
        throws Geary.EngineError.UNSUPPORTED {
        throw new Geary.EngineError.UNSUPPORTED("Mock method");
    }

    public void start_monitoring() {
        try {
            void_call("start_monitoring", {});
            this._is_monitoring = true;
        } catch (GLib.Error err) {
            // nooop
        }
    }

    public void stop_monitoring() {
        try {
            void_call("stop_monitoring", {});
            this._is_monitoring = false;
        } catch (GLib.Error err) {
            // noop
        }
    }

    public async void synchronise(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield void_call_async("synchronise", { cancellable });
    }

    public async void expand_vector(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield void_call_async("expand_vector", { cancellable });
    }

    public virtual Geary.Logging.State to_logging_state() {
        return new Geary.Logging.State(this, this.path.to_string());
    }

}
