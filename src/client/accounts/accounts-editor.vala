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
public class Accounts.Editor : Gtk.Dialog {


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
    public new Application.Client application {
        get { return (Application.Client) base.get_application(); }
        set { base.set_application(value); }
    }

    internal Manager accounts { get; private set; }

    internal Application.CertificateManager certificates {
        get; private set;
    }

    private GLib.SimpleActionGroup edit_actions = new GLib.SimpleActionGroup();

    [GtkChild] private unowned Gtk.Overlay notifications_pane;

    [GtkChild] private unowned Gtk.Stack editor_panes;

    private EditorListPane editor_list_pane;

    private Gee.LinkedList<EditorPane> editor_pane_stack =
        new Gee.LinkedList<EditorPane>();


    public Editor(Application.Client application, Gtk.Window parent) {
        this.application = application;
        this.transient_for = parent;
        this.icon_name = Application.Client.APP_ID;

        this.accounts = application.controller.account_manager;
        this.certificates = application.controller.certificate_manager;

        // Can't set this in Glade 3.22.1 :(
        this.get_content_area().border_width = 0;

        this.accounts = application.controller.account_manager;

        this.edit_actions.add_action_entries(EDIT_ACTIONS, this);
        insert_action_group(Action.Edit.GROUP_NAME, this.edit_actions);

        this.editor_list_pane = new EditorListPane(this);
        push(this.editor_list_pane);

        update_command_actions();

        if (this.accounts.size > 1) {
            this.default_height = 650;
            this.default_width = 800;
        } else {
            // Welcome dialog
            this.default_width = 600;
        }
    }

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;

        // Allow the user to use Esc, Back and Alt+arrow keys to
        // navigate between panes. If a pane is executing a long
        // running operation, only allow Esc and use it to cancel the
        // operation instead.
        EditorPane? current_pane = get_current_pane();
        if (current_pane != null &&
            current_pane != this.editor_list_pane) {
            Gdk.ModifierType state = (
                event.state & Gtk.accelerator_get_default_mod_mask()
            );
            bool is_ltr = (get_direction() == Gtk.TextDirection.LTR);

            switch (event.keyval) {
            case Gdk.Key.Escape:
                if (current_pane.is_operation_running) {
                    current_pane.cancel_operation();
                } else {
                    pop();
                }
                ret = Gdk.EVENT_STOP;
                break;

            case Gdk.Key.Back:
                if (!current_pane.is_operation_running) {
                    pop();
                    ret = Gdk.EVENT_STOP;
                }
                break;

            case Gdk.Key.Left:
                if (!current_pane.is_operation_running &&
                    state == Gdk.ModifierType.MOD1_MASK &&
                    is_ltr) {
                    pop();
                    ret = Gdk.EVENT_STOP;
                }
                break;

            case Gdk.Key.Right:
                if (!current_pane.is_operation_running &&
                    state == Gdk.ModifierType.MOD1_MASK &&
                    !is_ltr) {
                    pop();
                    ret = Gdk.EVENT_STOP;
                }
                break;
            }

        }

        if (ret != Gdk.EVENT_STOP) {
            ret = base.key_press_event(event);
        }

        return ret;
    }

    /**
     * Adds and shows a new pane in the editor.
     */
    internal void push(EditorPane pane) {
        // Since we keep old, already-popped panes around (see pop for
        // details), when a new pane is pushed on they need to be
        // truncated.
        EditorPane current = get_current_pane();
        int target_length = this.editor_pane_stack.index_of(current) + 1;
        while (target_length < this.editor_pane_stack.size) {
            EditorPane old = this.editor_pane_stack.remove_at(target_length);
            this.editor_panes.remove(old);
        }

        // Now push the new pane on
        this.editor_pane_stack.add(pane);
        this.editor_panes.add(pane);
        this.editor_panes.set_visible_child(pane);
    }

    /**
     * Removes the current pane from the editor, showing the last one.
     */
    internal void pop() {
        // One can't simply remove old panes for the GTK stack since
        // there won't be any transition between them - the old one
        // will simply disappear. So we need to keep old, popped panes
        // around until a new one is pushed on.
        EditorPane current = get_current_pane();
        int prev_index = this.editor_pane_stack.index_of(current) - 1;
        EditorPane prev = this.editor_pane_stack.get(prev_index);
        this.editor_panes.set_visible_child(prev);
    }

    /** Displays an in-app notification in the dialog. */
    internal void add_notification(Components.InAppNotification notification) {
        this.notifications_pane.add_overlay(notification);
        notification.show();
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
                this, account, service, endpoint, true, cancellable
            );
        } catch (Application.CertificateManagerError.UNTRUSTED err) {
            throw err;
        } catch (Application.CertificateManagerError.STORE_FAILED err) {
            // XXX show error info bar rather than a notification?
            add_notification(
                new Components.InAppNotification(
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
        this.editor_panes.set_visible_child(this.editor_list_pane);
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
        return this.editor_panes.get_visible_child() as EditorPane;
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

    [GtkCallback]
    private void on_pane_changed() {
        EditorPane? visible = get_current_pane();
        Gtk.Widget? header = null;
        if (visible != null) {
            // Do this in an idle callback since it's not 100%
            // reliable to just call it here for some reason. :(
            GLib.Idle.add(() => {
                    visible.initial_widget.grab_focus();
                    return GLib.Source.REMOVE;
                });
            header = visible.get_header();
        }
        set_titlebar(header);
        update_command_actions();
    }

}


// XXX I'd really like to make EditorPane an abstract class,
// AccountPane an abstract class extending that, and the four concrete
// panes extend those, but the GTK+ Builder XML template system
// requires a template class to designate its immediate parent
// class. I.e. if accounts-editor-list-pane.ui specifies GtkGrid as
// the parent of EditorListPane, then it much exactly be that and not
// an instance of EditorPane, even if that extends GtkGrid. As a
// result, both EditorPane and AccountPane must both be interfaces so
// that the concrete pane classes can derive from GtkGrid directly,
// and everything becomes horrible. See GTK+ Issue #1151:
// https://gitlab.gnome.org/GNOME/gtk/issues/1151

/**
 * Base interface for panes that can be shown by the accounts editor.
 */
internal interface Accounts.EditorPane : Gtk.Grid {


    /** The editor displaying this pane. */
    internal abstract weak Accounts.Editor editor { get; set; }

    /** The editor displaying this pane. */
    internal abstract Gtk.Widget initial_widget { get; }

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

    /** The GTK header bar to display for this pane. */
    internal abstract Gtk.HeaderBar get_header();

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

    /**
     * Called when an account has changed.
     *
     * By default, updates the editor's header subtitle.
     */
    private void account_changed() {
        update_header();
    }

    private inline void update_header() {
        get_header().subtitle = this.account.display_name;
    }

    private void on_account_changed() {
        account_changed();
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
