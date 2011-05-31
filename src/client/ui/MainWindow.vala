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
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Geary.Engine? engine = null;
    private Geary.Account? account = null;
    
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
        
        folder_list_view = new FolderListView(folder_list_store);
        folder_list_view.folder_selected.connect(on_folder_selected);
        
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
            
            Gee.Collection<string>? folders = yield account.list("/");
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
        
        // three-pane display: folder list on left, message list on right, separated with grippable
        // pane
        Gtk.HPaned paned = new Gtk.HPaned();
        
        // folder list
        Gtk.ScrolledWindow folder_list_scrolled = new Gtk.ScrolledWindow(null, null);
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add_with_viewport(folder_list_view);
        paned.pack1(folder_list_scrolled, false, false);
        
        // message list
        Gtk.ScrolledWindow message_list_scrolled = new Gtk.ScrolledWindow(null, null);
        message_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_list_scrolled.add_with_viewport(message_list_view);
        paned.pack2(message_list_scrolled, true, false);
        
        main_layout.pack_end(paned, true, true, 0);
        
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
    
    private void on_folder_selected(string folder) {
        do_select_folder.begin(folder, on_select_folder_completed);
    }
    
    private async void do_select_folder(string folder_name) throws Error {
        message_list_store.clear();
        
        Geary.Folder folder = yield account.open(folder_name);
        
        Gee.List<Geary.Message>? msgs = yield folder.read(1, 100);
        if (msgs != null && msgs.size > 0) {
            foreach (Geary.Message msg in msgs)
                message_list_store.append_message(msg);
        }
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
}

