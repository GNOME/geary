/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A folder of any type in the folder list.
public class FolderList.FolderEntry :
    FolderList.AbstractFolderEntry,
    Sidebar.InternalDropTargetEntry,
    Sidebar.EmphasizableEntry {


    private Application.FolderContext context;
    private Geary.RemoteFolder? remote;
    private bool has_new;


    public FolderEntry(Application.FolderContext context) {
        base(context.folder);
        this.context = context;
        this.context.notify.connect(on_context_changed);
        this.remote = context.folder as Geary.RemoteFolder;
        this.has_new = false;
        this.folder.notify["email-total"].connect(on_counts_changed);
        this.folder.notify["email-unread"].connect(on_counts_changed);
        if (this.remote != null) {
            this.remote.remote_properties.notify["email-total"].connect(
                on_counts_changed
            );
        }
    }

    ~FolderEntry() {
        this.context.notify.disconnect(on_context_changed);
        this.folder.notify["email-total"].disconnect(on_counts_changed);
        this.folder.notify["email-unread"].disconnect(on_counts_changed);
        if (this.remote != null) {
            this.remote.remote_properties.notify["email-total"].disconnect(
                on_counts_changed
            );
        }
    }

    public override string get_sidebar_name() {
        return this.context.display_name;
    }

    public override string? get_sidebar_tooltip() {
        string? tooltip = null;

        int local_total = this.remote.email_total;
        int local_unread = this.remote.email_unread;
        int remote_total = local_total;
        if (this.remote != null) {
            remote_total = this.remote.remote_properties.email_total;
        }

        if (local_total == remote_total) {
            // Translators: Tooltip displaying total number of email
            // messages in a folder. The string substitution is the
            // actual number.
            tooltip = ngettext(
                "%d message", "%d messages", folder.email_total
            ).printf(local_total);
        } else {
            // Translators: Tooltip displaying total number of email
            // messages locally in a folder and the total of number in
            // the remote folder. The first string substitution is the
            // local number, the second is the remote number.
            tooltip = ngettext(
                "%d of %d messages", "%d of %d messages", remote_total
            ).printf(
                local_total,
                remote_total
            );
        }

        if (local_unread > 0) {
            // Translators: Tooltip displaying number of unread email
            // messages in a folder. The string substitution is the
            // actual number.
            string unread_msg = ngettext(
                "%d unread", "%d unread", local_unread
            ).printf(local_unread);

            // Translators: Tooltip string that combines two messages:
            // "n messages" and "n unread".  Please use your languages
            // conventions for combining the two, i.e. a comma (",")
            // for English; "6 messages, 3 unread"
            tooltip = _("%s, %s").printf(tooltip, unread_msg);
        }

        return tooltip;
    }

    public override string? get_sidebar_icon() {
        return this.context.icon_name;
    }

    public override string to_string() {
        return "FolderEntry: " + get_sidebar_name();
    }

    public bool is_emphasized() {
        return has_new;
    }

    public void set_has_new(bool has_new) {
        if (this.has_new == has_new)
            return;

        this.has_new = has_new;
        entry_changed();
    }

    public bool internal_drop_received(Application.MainWindow main_window,
                                       Gdk.DragContext context,
                                       Gtk.SelectionData data) {
        // Copy or move?
        Gdk.ModifierType mask;
        double[] axes = new double[2];
        context.get_device().get_state(context.get_dest_window(), axes, out mask);
        if ((mask & Gdk.ModifierType.CONTROL_MASK) != 0) {
            main_window.folder_list.copy_conversation(folder);
        } else {
            main_window.folder_list.move_conversation(folder);
        }

        return true;
    }

    public override int get_count() {
        switch (this.context.displayed_count) {
        case TOTAL:
            return folder.email_total;

        case UNREAD:
            return folder.email_unread;

        default:
            return 0;
        }
    }

    private void on_counts_changed() {
        entry_changed();
    }

    private void on_context_changed() {
        entry_changed();
    }

}
