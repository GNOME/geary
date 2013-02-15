/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A folder of any type in the folder list.
public class FolderList.FolderEntry : Object, Sidebar.Entry, Sidebar.InternalDropTargetEntry,
    Sidebar.SelectableEntry, Sidebar.EmphasizableEntry {
    public Geary.Folder folder { get; private set; }
    private bool has_unread;
    
    public FolderEntry(Geary.Folder folder) {
        this.folder = folder;
        has_unread = false;
    }
    
    public virtual string get_sidebar_name() {
        return folder.get_display_name();
    }
    
    public string? get_sidebar_tooltip() {
        return null;
    }
    
    public Icon? get_sidebar_icon() {
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
    
    public virtual string to_string() {
        return "FolderEntry: " + get_sidebar_name();
    }
    
    public bool is_emphasized() {
        return has_unread;
    }
    
    public void set_has_unread(bool has_unread) {
        if (this.has_unread == has_unread)
            return;
        
        this.has_unread = has_unread;
        is_emphasized_changed(has_unread);
    }

    public bool internal_drop_received(Gdk.DragContext context, Gtk.SelectionData data) {
        // Copy or move?
        Gdk.ModifierType mask;
        double[] axes = new double[2];
        context.get_device().get_state(context.get_dest_window(), axes, out mask);
        MainWindow main_window = GearyApplication.instance.get_main_window() as MainWindow;
        if ((mask & Gdk.ModifierType.CONTROL_MASK) != 0) {
            main_window.folder_list.copy_conversation(folder);
        } else {
            main_window.folder_list.move_conversation(folder);
        }

        return true;
    }
}
