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
    private Geary.Engine? engine = null;
    private Geary.Account? account = null;
    private Geary.Folder? current_folder = null;
    
    public MainWindow() {
        title = GearyApplication.PROGRAM_NAME;
        set_default_size(800, 600);
        
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
    
    public void login(Geary.Engine engine, string user, string pass) {
        this.engine = engine;
        
        do_login.begin(user, pass);
    }
    
    private async void do_login(string user, string pass) {
        try {
            account = yield engine.login("imap.gmail.com", user, pass);
            if (account == null)
                error("Unable to login");
            
            // pull down the root-level folders
            Gee.Collection<Geary.FolderDetail> folders = yield account.list(null);
            if (folders != null) {
                debug("%d folders found", folders.size);
                folder_list_store.add_folders(folders);
            } else {
                debug("no folders");
            }
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
            "program-name", GearyApplication.PROGRAM_NAME,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL
        );
    }
    
    private void on_folder_selected(string? folder) {
        if (folder == null) {
            message_list_store.clear();
            
            return;
        }
        
        do_select_folder.begin(folder, on_select_folder_completed);
    }
    
    private async void do_select_folder(string folder_name) throws Error {
        message_list_store.clear();
        
        current_folder = yield account.open(folder_name);
        
        Gee.List<Geary.EmailHeader>? headers = yield current_folder.read(1, 100);
        if (headers != null && headers.size > 0) {
            foreach (Geary.EmailHeader header in headers)
                message_list_store.append_header(header);
        }
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
    
    private void on_message_selected(Geary.EmailHeader? header) {
        if (header == null) {
            message_buffer.set_text("");
            
            return;
        }
        
        do_select_message.begin(header, on_select_message_completed);
    }
    
    private async void do_select_message(Geary.EmailHeader header) throws Error {
        if (current_folder == null) {
            debug("Message %s selected with no folder selected", header.to_string());
            
            return;
        }
        
        Geary.EmailBody body = yield current_folder.fetch_body(header);
        message_buffer.set_text(body.full);
    }
    
    private void on_select_message_completed(Object? source, AsyncResult result) {
        try {
            do_select_message.end(result);
        } catch (Error err) {
            debug("Unable to select message: %s", err.message);
        }
    }
}

