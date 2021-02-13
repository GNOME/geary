/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.Folder : GLib.Object,
    Geary.Logging.Source,
    Geary.Folder,
    ValaUnit.TestAssertions,
    ValaUnit.MockObject {


    public override Geary.Account account {
        get { return this._account; }
    }

    public override Geary.FolderProperties properties {
        get { return this._properties; }
    }

    public override Geary.Folder.Path path {
        get { return this._path; }
    }

    public override Geary.Folder.SpecialUse used_as {
        get { return this._used_as; }
    }

    public Geary.Logging.Source? logging_parent {
        get { return this.account; }
    }

    protected Gee.Queue<ValaUnit.ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
    }


    private Geary.Account _account;
    private Geary.FolderProperties _properties;
    private Geary.Folder.Path _path;
    private Geary.Folder.SpecialUse _used_as;
    private Geary.ProgressMonitor _opening_monitor;


    public Folder(Geary.Account? account,
                  Geary.FolderProperties? properties,
                  Geary.Folder.Path? path,
                  Geary.Folder.SpecialUse used_as,
                  Geary.ProgressMonitor? monitor) {
        this._account = account;
        this._properties = properties ?? new FolderPoperties();
        this._path = path;
        this._used_as = used_as;
        this._opening_monitor = monitor;
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

    public virtual Geary.Logging.State to_logging_state() {
        return new Geary.Logging.State(this, this.path.to_string());
    }

}
