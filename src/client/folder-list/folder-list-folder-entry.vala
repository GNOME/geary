/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A folder of any type in the folder list.
public class FolderList.FolderEntry : FolderList.AbstractFolderEntry, Sidebar.InternalDropTargetEntry,
    Sidebar.EmphasizableEntry {
    private bool has_new;
    
    public FolderEntry(Geary.Folder folder) {
        base(folder);
        has_new = false;
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL].connect(on_counts_changed);
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_UNREAD].connect(on_counts_changed);
        folder.display_name_changed.connect(on_display_name_changed);
    }
    
    ~FolderEntry() {
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL].disconnect(on_counts_changed);
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_UNREAD].disconnect(on_counts_changed);
        folder.display_name_changed.disconnect(on_display_name_changed);
    }
    
    public override string get_sidebar_name() {
        return folder.get_display_name();
    }
    
    public override string? get_sidebar_tooltip() {
        // Label displaying total number of email messages in a folder
        string total_msg = ngettext("%d message", "%d messages", folder.properties.email_total).
            printf(folder.properties.email_total);
        
        if (folder.properties.email_unread == 0)
            return total_msg;
        
        /// Label displaying number of unread email messages in a folder
        string unread_msg = ngettext("%d unread", "%d unread", folder.properties.email_unread).
            printf(folder.properties.email_unread);
        
        /// This string represents the divider between two messages: "n messages" and "n unread",
        /// shown in the folder list as a tooltip.  Please use your languages conventions for
        /// combining the two, i.e. a comma (",") for English; "6 messages, 3 unread"
        return _("%s, %s").printf(total_msg, unread_msg);
    }
    
    public override string? get_sidebar_icon() {
        bool rtl = Gtk.Widget.get_default_direction() == Gtk.TextDirection.RTL;
        
        switch (folder.special_folder_type) {
            case Geary.SpecialFolderType.NONE:
                return rtl ? "tag-rtl-symbolic" : "tag-symbolic";
            
            case Geary.SpecialFolderType.INBOX:
                return "mail-inbox-symbolic";
            
            case Geary.SpecialFolderType.DRAFTS:
                return "accessories-text-editor-symbolic";
            
            case Geary.SpecialFolderType.SENT:
                return rtl ? "mail-sent-rtl-symbolic" : "mail-sent-symbolic";
            
            case Geary.SpecialFolderType.FLAGGED:
                return "starred-symbolic";
            
            case Geary.SpecialFolderType.IMPORTANT:
                return "task-due-symbolic";
            
            case Geary.SpecialFolderType.ALL_MAIL:
                return "mail-archive-symbolic";
            
            case Geary.SpecialFolderType.SPAM:
                return rtl ? "mail-spam-rtl-symbolic" : "mail-spam-symbolic";
            
            case Geary.SpecialFolderType.TRASH:
                return "user-trash-symbolic";
            
            case Geary.SpecialFolderType.OUTBOX:
                return "mail-outbox-symbolic";
            
            default:
                assert_not_reached();
        }
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
        is_emphasized_changed(has_new);
    }
    
    public bool internal_drop_received(Gdk.DragContext context, Gtk.SelectionData data) {
        // Copy or move?
        Gdk.ModifierType mask;
        double[] axes = new double[2];
        context.get_device().get_state(context.get_dest_window(), axes, out mask);
        MainWindow main_window = GearyApplication.instance.controller.main_window;
        if ((mask & Gdk.ModifierType.CONTROL_MASK) != 0) {
            main_window.folder_list.copy_conversation(folder);
        } else {
            main_window.folder_list.move_conversation(folder);
        }

        return true;
    }
    
    private void on_counts_changed() {
        sidebar_count_changed(get_count());
        sidebar_tooltip_changed(get_sidebar_tooltip());
    }
    
    private void on_display_name_changed() {
        sidebar_name_changed(folder.get_display_name());
    }
    
    public override int get_count() {
        switch (folder.special_folder_type) {
            // for Drafts and Outbox, interested in showing total count, not unread count
            case Geary.SpecialFolderType.DRAFTS:
            case Geary.SpecialFolderType.OUTBOX:
                return folder.properties.email_total;
            
            // only show counts for Inbox, Spam, and user folders
            case Geary.SpecialFolderType.INBOX:
            case Geary.SpecialFolderType.SPAM:
            case Geary.SpecialFolderType.NONE:
                return folder.properties.email_unread;
            
            // otherwise, to avoid clutter, no counts displayed (but are available in tooltip)
            default:
                return 0;
        }
    }
}
