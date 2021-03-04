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


    public class RemoteProperties : GLib.Object,
        Geary.RemoteFolder.RemoteProperties {


        public int email_total { get; protected set; default = 0; }

        public int email_unread { get; protected set; default = 0; }

        public Geary.Trillian has_children {
            get; protected set; default = Geary.Trillian.UNKNOWN;
        }

        public Geary.Trillian supports_children {
            get; protected set; default = Geary.Trillian.UNKNOWN;
        }

        public Geary.Trillian is_openable {
            get; protected set; default = Geary.Trillian.UNKNOWN;
        }

        public bool create_never_returns_id {
            get; protected set; default = false;
        }

    }

    public Geary.Account account {
        get { return this._account; }
    }

    public Geary.RemoteFolder.RemoteProperties remote_properties {
        get { return this._remote_properties; }
    }

    public Geary.Folder.Path path {
        get { return this._path; }
    }

    public override int email_total {
        get { return this._email_total; }
    }

    public override int email_unread {
        get { return this._email_unread; }
    }

    public Geary.Folder.SpecialUse used_as {
        get { return this._used_as; }
    }

    public bool is_fully_expanded {
        get { return this._is_fully_expanded; }
    }
    private bool _is_fully_expanded = false;

    public bool is_monitoring {
        get { return this._is_monitoring; }
    }
    private bool _is_monitoring = false;

    public Geary.Logging.Source? logging_parent {
        get { return this.account; }
    }

    protected Gee.Queue<ValaUnit.ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
    }


    private Geary.Account _account;
    private Geary.RemoteFolder.RemoteProperties _remote_properties;
    private Geary.Folder.Path _path;
    private int _email_total = 0;
    private int _email_unread = 0;
    private Geary.Folder.SpecialUse _used_as;
    private Geary.ProgressMonitor _opening_monitor;


    public RemoteFolder(Geary.Account? account,
                        Geary.RemoteFolder.RemoteProperties? remote_properties,
                        Geary.Folder.Path? path,
                        Geary.Folder.SpecialUse used_as,
                        Geary.ProgressMonitor? monitor,
                        bool is_monitoring,
                        bool is_fully_expanded) {
        this._account = account;
        this._remote_properties = remote_properties ?? new RemoteProperties();
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

    public async Geary.Email get_email_by_id(
        Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields = ALL,
        Geary.Folder.GetFlags flags = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return object_or_throw_call<Geary.Email>(
            "get_email_by_id",
            {email_id, box_arg(required_fields), box_arg(flags), cancellable},
            new Geary.EngineError.UNSUPPORTED("Mock method")
        );
    }

    public async Gee.Set<Geary.Email> get_multiple_email_by_id(
        Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields = ALL,
        Geary.Folder.GetFlags flags = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return object_or_throw_call<Gee.Set<Geary.Email>>(
            "get_multiple_email_by_id",
            {ids, box_arg(required_fields), box_arg(flags), cancellable},
            new Geary.EngineError.UNSUPPORTED("Mock method")
        );
    }

    public async Gee.List<Geary.Email>
        list_email_range_by_id(Geary.EmailIdentifier? initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Geary.Folder.ListFlags flags,
                               GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_or_throw_call<Gee.List<Geary.Email>>(
            "list_email_range_by_id",
            {initial_id, int_arg(count), box_arg(required_fields), box_arg(flags), cancellable},
            new Geary.EngineError.UNSUPPORTED("Mock method")
        );
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

    public async void expand_vector(GLib.DateTime? target_date,
                                    uint? target_count,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield void_call_async(
            "expand_vector",
            { box_arg(target_date), box_arg(target_count), cancellable }
        );
    }

    public virtual Geary.Logging.State to_logging_state() {
        return new Geary.Logging.State(this, this.path.to_string());
    }

}
