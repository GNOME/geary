/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The main account editor window.
 *
 * The editor is a dialog window that manages a stack of {@link
 * EditorPane} instances. Each pane handles a specific task (listing
 * accounts, adding a new account, editing an existing one, etc.). The
 * editor displaying panes as needed, and provides some common command
 * management, account management and other common code for the panes.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor.ui")]
public class Accounts.Editor : Adw.Dialog {


    private const ActionEntry[] EDIT_ACTIONS = {
        { Action.Edit.REDO, on_redo },
        { Action.Edit.UNDO, on_undo },
    };


    internal static void seperator_headers(Gtk.ListBoxRow row,
                                           Gtk.ListBoxRow? first) {
        if (first == null) {
            row.set_header(null);
        } else if (row.get_header() == null) {
            row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
        }
    }


    /** Returns the editor's associated client application instance. */
    public Application.Client application { get; private set; }

    internal Manager accounts { get; private set; }

    internal Application.CertificateManager certificates {
        get; private set;
    }

    private GLib.SimpleActionGroup edit_actions = new GLib.SimpleActionGroup();

    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;

    [GtkChild] private unowned Adw.NavigationView view;

    private EditorListPane editor_list_pane;


    public Editor(Application.Client application) {
        this.application = application;

        this.accounts = application.controller.account_manager;
        this.certificates = application.controller.certificate_manager;

        this.accounts = application.controller.account_manager;

        this.edit_actions.add_action_entries(EDIT_ACTIONS, this);
        insert_action_group(Action.Edit.GROUP_NAME, this.edit_actions);

        this.editor_list_pane = new EditorListPane(this);
        push_pane(this.editor_list_pane);

        update_command_actions();
    }

    [GtkCallback]
    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType mod_state) {
        bool ret = Gdk.EVENT_PROPAGATE;

        // XXX GTK4 - we'll need to disable the esc behavio in adwnavigationview and then do it manually here
        // Allow the user to use Esc, Back and Alt+arrow keys to
        // navigate between panes. If a pane is executing a long
        // running operation, only allow Esc and use it to cancel the
        // operation instead.
        EditorPane? current_pane = get_current_pane();
        if (current_pane != null &&
            current_pane != this.editor_list_pane) {

            if (keyval == Gdk.Key.Escape) {
                if (current_pane.is_operation_running) {
                    current_pane.cancel_operation();
                } else {
                    pop_pane();
                }
                ret = Gdk.EVENT_STOP;
            }
        }

        return ret;
    }

    /**
     * Adds and shows a new pane in the editor.
     */
    internal void push_pane(EditorPane pane) {
        this.view.push(pane);
    }

    /**
     * Removes the current pane from the editor, showing the last one.
     */
    internal bool pop_pane() {
        return this.view.pop();
    }

    /** Displays an in-app notification in the dialog. */
    internal void add_toast(Adw.Toast toast) {
        this.toast_overlay.add_toast(toast);
    }

    /**
     * Prompts for pinning a certificate using the certificate manager.
     *
     * This provides a thing wrapper around {@link
     * Application.CertificateManager.prompt_pin_certificate} that
     * uses the account editor as the dialog parent.
     */
    internal async void prompt_pin_certificate(Geary.AccountInformation account,
                                               Geary.ServiceInformation service,
                                               Geary.Endpoint endpoint,
                                               GLib.Cancellable? cancellable)
        throws Application.CertificateManagerError {
        try {
            yield this.certificates.prompt_pin_certificate(
                get_root() as Gtk.Window, account, service, endpoint, true, cancellable
            );
        } catch (Application.CertificateManagerError.UNTRUSTED err) {
            throw err;
        } catch (Application.CertificateManagerError.STORE_FAILED err) {
            // XXX show error info bar rather than a notification?
            add_toast(
                new Adw.Toast(
                    // Translators: In-app notification label, when
                    // the app had a problem pinning an otherwise
                    // untrusted TLS certificate
                    _("Failed to store certificate")
                )
            );
            throw err;
        } catch (Application.CertificateManagerError err) {
            debug("Unexpected error pinning cert: %s", err.message);
            throw err;
        }
    }

    /** Removes an account from the editor. */
    internal void remove_account(Geary.AccountInformation account) {
        this.view.pop_to_page(this.editor_list_pane);
        this.editor_list_pane.remove_account(account);
    }

    /** Updates the state of the editor's undo and redo actions. */
    internal void update_command_actions() {
        bool can_undo = false;
        bool can_redo = false;
        CommandPane? pane = get_current_pane() as CommandPane;
        if (pane != null) {
            can_undo = pane.commands.can_undo;
            can_redo = pane.commands.can_redo;
        }

        get_action(Action.Edit.UNDO).set_enabled(can_undo);
        get_action(Action.Edit.REDO).set_enabled(can_redo);
    }

    private inline EditorPane? get_current_pane() {
        return this.view.visible_page as EditorPane;
    }

    private inline GLib.SimpleAction get_action(string name) {
        return (GLib.SimpleAction) this.edit_actions.lookup_action(name);
    }

    private void on_undo() {
        CommandPane? pane = get_current_pane() as CommandPane;
        if (pane != null) {
            pane.undo();
        }
    }

    private void on_redo() {
        CommandPane? pane = get_current_pane() as CommandPane;
        if (pane != null) {
            pane.redo();
        }
    }
}


/**
 * Base interface for panes that can be shown by the accounts editor.
 */
internal abstract class Accounts.EditorPane : Adw.NavigationPage {


    /** The editor displaying this pane. */
    internal abstract weak Accounts.Editor editor { get; set; }

    /**
     * Determines if a long running operation is being executed.
     *
     * @see cancel_operation
     */
    internal abstract bool is_operation_running { get; protected set; }

    /**
     * Long running operation cancellable.
     *
     * This cancellable must be passed to any long-running operations
     * involving I/O. If not null and operation is cancelled, the
     * value should be cancelled and replaced with a new instance.
     *
     * @see cancel_operation
     */
    internal abstract GLib.Cancellable? op_cancellable { get; protected set; }

    /**
     * Cancels this pane's current operation, any.
     *
     * Sets {@link is_operation_running} to false and if {@link
     * op_cancellable} is not null, it is cancelled and replaced with
     * a new instance.
     */
    internal void cancel_operation() {
        this.is_operation_running = false;
        if (this.op_cancellable != null) {
            this.op_cancellable.cancel();
            this.op_cancellable = new GLib.Cancellable();
        }
    }
}


/**
 * Interface for editor panes that display a specific account.
 */
internal interface Accounts.AccountPane : EditorPane {


    /** Account being displayed by this pane. */
    internal abstract Geary.AccountInformation account { get; protected set; }


    /**
     * Connects to account signals.
     *
     * Implementing classes should call this in their constructor.
     */
    protected void connect_account_signals() {
        this.account.changed.connect(on_account_changed);
        update_header();
    }

    /**
     * Disconnects from account signals.
     *
     * Implementing classes should call this in their destructor.
     */
    protected void disconnect_account_signals() {
        this.account.changed.disconnect(on_account_changed);
    }

    private void on_account_changed() {
        update_header();
    }

    private inline void update_header() {
        // XXX GTK4 - this was subtitle before, will need to make the title subtitle
        this.title = this.account.display_name;
    }

}

/**
 * Interface for editor panes that support undoing/redoing user actions.
 */
internal interface Accounts.CommandPane : EditorPane {


    /** Stack for the user's commands. */
    internal abstract Application.CommandStack commands { get; protected set; }


    /** Un-does the last user action, if enabled. */
    internal virtual void undo() {
        this.commands.undo.begin(null);
    }

    /** Re-does the last user action, if enabled. */
    internal virtual void redo() {
        this.commands.redo.begin(null);
    }

    /**
     * Connects to command stack signals.
     *
     * Implementing classes should call this in their constructor.
     */
    protected void connect_command_signals() {
        this.commands.executed.connect(on_command);
        this.commands.undone.connect(on_command);
        this.commands.redone.connect(on_command);
    }

    /**
     * Disconnects from command stack signals.
     *
     * Implementing classes should call this in their destructor.
     */
    protected void disconnect_command_signals() {
        this.commands.executed.disconnect(on_command);
        this.commands.undone.disconnect(on_command);
        this.commands.redone.disconnect(on_command);
    }

    /**
     * Called when a command is executed, undone or redone.
     *
     * By default, calls {@link Accounts.Editor.update_command_actions}.
     */
    protected virtual void command_executed() {
        this.editor.update_command_actions();
    }

    private void on_command() {
        command_executed();
    }

}
