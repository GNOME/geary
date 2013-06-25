/* Copyright 2011-2013 Yorba Foundation
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
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_UNREAD].connect(
            on_email_unread_count_changed);
    }
    
    ~FolderEntry() {
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_UNREAD].disconnect(
            on_email_unread_count_changed);
    }
    
    public override string get_sidebar_name() {
        return (folder.properties.email_unread == 0 ? folder.get_display_name() :
            /// This string gets the folder name and the unread messages count,
            /// e.g. All Mail (5).
            _("%s (%d)").printf(folder.get_display_name(), folder.properties.email_unread));
    }
    
    public override string? get_sidebar_tooltip() {
        return (folder.properties.email_unread == 0 ? null :
            ngettext("%d unread message", "%d unread messages", folder.properties.email_unread).
            printf(folder.properties.email_unread));
    }
    
    public override Icon? get_sidebar_icon() {
        switch (folder.get_special_folder_type()) {
            case Geary.SpecialFolderType.NONE:
                return IconFactory.instance.get_custom_icon("tag", IconFactory.ICON_SIDEBAR);
            
            case Geary.SpecialFolderType.INBOX:
                return new ThemedIcon("mail-inbox");
            
            case Geary.SpecialFolderType.DRAFTS:
                return new ThemedIcon("accessories-text-editor");
            
            case Geary.SpecialFolderType.SENT:
                return new ThemedIcon("mail-sent");
            
            case Geary.SpecialFolderType.FLAGGED:
                return new ThemedIcon("starred");
            
            case Geary.SpecialFolderType.IMPORTANT:
                return new ThemedIcon("task-due");
            
            case Geary.SpecialFolderType.ALL_MAIL:
                return IconFactory.instance.get_custom_icon("mail-archive", IconFactory.ICON_SIDEBAR);
            
            case Geary.SpecialFolderType.SPAM:
                return new ThemedIcon("mail-mark-junk");
            
            case Geary.SpecialFolderType.TRASH:
                return new ThemedIcon("user-trash");
            
            case Geary.SpecialFolderType.OUTBOX:
                return new ThemedIcon("mail-outbox");
            
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
    
    private void on_email_unread_count_changed() {
        sidebar_name_changed(get_sidebar_name());
        sidebar_tooltip_changed(get_sidebar_tooltip());
    }
}
