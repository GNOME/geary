/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MainWindow : Gtk.Window {
    private const string MAIN_MENU_XML = """
<ui>
    <menubar name="MenuBar">
        <menu name="FileMenu" action="FileMenu">
            <menuitem name="Quit" action="FileQuit" />
        </menu>
        
        <menu name="HelpMenu" action="HelpMenu">
            <menuitem name="About" action="HelpAbout" />
        </menu>
    </menubar>
</ui>
""";
    
    private MessageListStore message_list_store = new MessageListStore();
    private MessageListView message_list_view;
    private FolderListStore folder_list_store = new FolderListStore();
    private FolderListView folder_list_view;
    private MessageViewer message_viewer = new MessageViewer();
    private MessageBuffer message_buffer = new MessageBuffer();
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Geary.EngineAccount? account = null;
    private Geary.Folder? current_folder = null;
    
    public MainWindow() {
        title = GearyApplication.NAME;
        set_default_size(862, 684);
        
        try {
            ui.add_ui_from_string(MAIN_MENU_XML, -1);
        } catch (Error err) {
            error("Unable to load main menu UI: %s", err.message);
        }
        
        Gtk.ActionGroup action_group = new Gtk.ActionGroup("MainMenuActionGroup");
        action_group.add_actions(create_actions(), this);
        
        ui.insert_action_group(action_group, 0);
        add_accel_group(ui.get_accel_group());
        
        message_list_view = new MessageListView(message_list_store);
        message_list_view.message_selected.connect(on_message_selected);
        
        folder_list_view = new FolderListView(folder_list_store);
        folder_list_view.folder_selected.connect(on_folder_selected);
        
        message_viewer.set_buffer(message_buffer);
        
        create_layout();
    }
    
    ~MainWindow() {
        if (account != null)
            account.folders_added_removed.disconnect(on_folders_added_removed);
    }
    
    public void start(Geary.EngineAccount account) {
        this.account = account;
        account.folders_added_removed.connect(on_folders_added_removed);
        
        folder_list_store.set_user_folders_root_name(account.get_user_folders_label());
        
        do_start.begin();
    }
    
    private async void do_start() {
        try {
            // add all the special folders, which are assumed to always exist
            Geary.SpecialFolderMap? special_folders = account.get_special_folder_map();
            if (special_folders != null) {
                foreach (Geary.SpecialFolder special_folder in special_folders.get_all()) {
                    Geary.Folder folder = yield account.fetch_folder_async(special_folder.path);
                    folder_list_store.add_special_folder(special_folder, folder);
                }
                
                // If inbox is specified, select that
                Geary.SpecialFolder? inbox = special_folders.get_folder(Geary.SpecialFolderType.INBOX);
                if (inbox != null)
                    folder_list_view.select_path(inbox.path);
            }
            
            // pull down the root-level user folders
            Gee.Collection<Geary.Folder> folders = yield account.list_folders_async(null);
            if (folders != null)
                on_folders_added_removed(folders, null);
            else
                debug("no folders");
        } catch (Error err) {
            error("%s", err.message);
        }
    }
    
    public override void destroy() {
        GearyApplication.instance.exit();
        
        base.destroy();
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        //
        // File
        //
        
        Gtk.ActionEntry file_menu = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file_menu.label = _("_File");
        entries += file_menu;
        
        Gtk.ActionEntry quit = { "FileQuit", Gtk.Stock.QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        //
        // Help
        //
        
        Gtk.ActionEntry help_menu = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help_menu.label = _("_Help");
        entries += help_menu;
        
        Gtk.ActionEntry about = { "HelpAbout", Gtk.Stock.ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        return entries;
    }
    
    private void create_layout() {
        Gtk.VBox main_layout = new Gtk.VBox(false, 0);
        
        // main menu
        main_layout.pack_start(ui.get_widget("/MenuBar"), false, false, 0);
        
        Gtk.HPaned folder_paned = new Gtk.HPaned();
        Gtk.VPaned messages_paned = new Gtk.VPaned();
        
        // folder list
        Gtk.ScrolledWindow folder_list_scrolled = new Gtk.ScrolledWindow(null, null);
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add_with_viewport(folder_list_view);
        
        // message list
        Gtk.ScrolledWindow message_list_scrolled = new Gtk.ScrolledWindow(null, null);
        message_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_list_scrolled.add_with_viewport(message_list_view);
        
        // message viewer
        Gtk.ScrolledWindow message_viewer_scrolled = new Gtk.ScrolledWindow(null, null);
        message_viewer_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_viewer_scrolled.add(message_viewer);
        
        // three-pane display: message list on top and current message on bottom separated by
        // grippable
        messages_paned.pack1(message_list_scrolled, true, false);
        messages_paned.pack2(message_viewer_scrolled, true, false);
        
        // three-pane display: folder list on left and messages on right separated by grippable
        folder_paned.pack1(folder_list_scrolled, false, false);
        folder_paned.pack2(messages_paned, true, false);
        
        main_layout.pack_end(folder_paned, true, true, 0);
        
        add(main_layout);
    }
    
    private void on_quit() {
        GearyApplication.instance.exit();
    }
    
    private void on_about() {
        Gtk.show_about_dialog(this,
            "program-name", GearyApplication.NAME,
            "comments", GearyApplication.DESCRIPTION,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL
        );
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        if (folder == null) {
            debug("no folder selected");
            message_list_store.clear();
            
            return;
        }
        
        debug("Folder %s selected", folder.to_string());
        
        do_select_folder.begin(folder, on_select_folder_completed);
    }
    
    private async void do_select_folder(Geary.Folder folder) throws Error {
        message_list_store.clear();
        
        if (current_folder != null) {
            current_folder.email_added_removed.disconnect(on_email_added_removed);
            yield current_folder.close_async();
        }
        
        current_folder = folder;
        current_folder.email_added_removed.connect(on_email_added_removed);
        
        yield current_folder.open_async(true);
        
        current_folder.lazy_list_email_async(1, 1000, Geary.Email.Field.ENVELOPE,
            on_list_email_ready);
    }
    
    private void on_list_email_ready(Gee.List<Geary.Email>? email, Error? err) {
        if (email != null && email.size > 0) {
            foreach (Geary.Email envelope in email)
                message_list_store.append_envelope(envelope);
        }
        
        if (err != null)
            debug("Error while listing email: %s", err.message);
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
    
    private void on_message_selected(Geary.Email? email) {
        if (email == null) {
            message_buffer.set_text("");
            
            return;
        }
        
        do_select_message.begin(email, on_select_message_completed);
    }
    
    private async void do_select_message(Geary.Email email) throws Error {
        if (current_folder == null) {
            debug("Message %s selected with no folder selected", email.to_string());
            
            return;
        }
        
        Geary.Email full = yield current_folder.fetch_email_async(email.location.position,
            Geary.Email.Field.HEADER | Geary.Email.Field.BODY);
        
        Geary.Memory.AbstractBuffer buffer = full.get_message().get_first_mime_part_of_content_type(
            "text/plain");
        
        message_buffer.set_text(buffer.to_utf8());
    }
    
    private void on_select_message_completed(Object? source, AsyncResult result) {
        try {
            do_select_message.end(result);
        } catch (Error err) {
            debug("Unable to select message: %s", err.message);
        }
    }
    
    private void on_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        if (added != null && added.size > 0) {
            Gee.Set<Geary.FolderPath>? ignored_paths = account.get_ignored_paths();
            
            Gee.ArrayList<Geary.Folder> skipped = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Folder folder in added) {
                if (ignored_paths != null && ignored_paths.contains(folder.get_path()))
                    skipped.add(folder);
                else
                    folder_list_store.add_user_folder(folder);
            }
            
            Gee.Collection<Geary.Folder> remaining = added;
            if (skipped.size > 0) {
                remaining = new Gee.ArrayList<Geary.Folder>();
                remaining.add_all(added);
                remaining.remove_all(skipped);
            }
            
            search_folders_for_children.begin(remaining);
        }
    }
    
    private void on_email_added_removed(Gee.List<Geary.Email>? added, Gee.List<Geary.Folder>? removed) {
        if (added != null) {
            foreach (Geary.Email email in added)
                message_list_store.append_envelope(email);
        }
    }
    
    private async void search_folders_for_children(Gee.Collection<Geary.Folder> folders) {
        Gee.ArrayList<Geary.Folder> accumulator = new Gee.ArrayList<Geary.Folder>();
        foreach (Geary.Folder folder in folders) {
            try {
                Gee.Collection<Geary.Folder> children = yield account.list_folders_async(
                    folder.get_path(), null);
                accumulator.add_all(children);
            } catch (Error err) {
                debug("Unable to list children of %s: %s", folder.to_string(), err.message);
            }
        }
        
        if (accumulator.size > 0)
            on_folders_added_removed(accumulator, null);
    }
}

