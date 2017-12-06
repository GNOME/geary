/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockFolder : Folder {

    public override Account account {
        get { return this._account; }
    }

    public override FolderProperties properties {
        get { return this._properties; }
    }

    public override FolderPath path {
        get { return this._path; }
    }

    public override SpecialFolderType special_folder_type {
        get { return this._type; }
    }

    public override ProgressMonitor opening_monitor {
        get { return this._opening_monitor; }
    }

    private Account _account;
    private FolderProperties _properties;
    private FolderPath _path;
    private SpecialFolderType _type;
    private ProgressMonitor _opening_monitor;


    public MockFolder(Account? account,
                      FolderProperties? properties,
                      FolderPath? path,
                      SpecialFolderType type,
                      ProgressMonitor? monitor) {
        this._account = account;
        this._properties = properties;
        this._path = path;
        this._type = type;
        this._opening_monitor = monitor;
    }

    public override Folder.OpenState get_open_state() {
        return OpenState.CLOSED;
    }

    public override async bool open_async(Folder.OpenFlags open_flags,
                                 Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void wait_for_open_async(Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async bool close_async(Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void wait_for_close_async(Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void
        find_boundaries_async(Gee.Collection<Geary.EmailIdentifier> ids,
                          out Geary.EmailIdentifier? low,
                          out Geary.EmailIdentifier? high,
                          Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }


    public override async Gee.List<Geary.Email>?
        list_email_by_id_async(Geary.EmailIdentifier? initial_id,
                               int count,
                               Geary.Email.Field required_fields,
                               Folder.ListFlags flags,
                               Cancellable? cancellable = null)
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Gee.List<Geary.Email>?
        list_email_by_sparse_id_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Geary.Email.Field required_fields,
                                      Folder.ListFlags flags,
                                      Cancellable? cancellable = null)
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Gee.Map<Geary.EmailIdentifier, Geary.Email.Field>?
        list_local_email_fields_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                      Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Geary.Email
        fetch_email_async(Geary.EmailIdentifier email_id,
                          Geary.Email.Field required_fields,
                          Folder.ListFlags flags,
                          Cancellable? cancellable = null)
    throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

}
