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
    private Gtk.UIManager ui = new Gtk.UIManager();
    private Geary.Engine? engine = null;
    
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
        
        create_layout();
    }
    
    public void login(Geary.Engine engine, string user, string pass) {
        this.engine = engine;
        
        do_login.begin(user, pass);
    }
    
    private async void do_login(string user, string pass) {
        try {
            Geary.Account? account = yield engine.login("imap.gmail.com", user, pass);
            if (account == null)
                error("Unable to login");
            
            Geary.Folder folder = yield account.open("inbox");
            
            Geary.MessageStream? msg_stream = folder.read(1, 100);
            if (msg_stream == null)
                error("Unable to read from folder");
            
            Gee.List<Geary.Message>? msgs = yield msg_stream.read();
            if (msgs != null && msgs.size > 0) {
                foreach (Geary.Message msg in msgs)
                    message_list_store.append_message(msg);
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
        
        // message list
        Gtk.ScrolledWindow message_list_scrolled = new Gtk.ScrolledWindow(null, null);
        message_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_list_scrolled.add_with_viewport(message_list_view);
        main_layout.pack_end(message_list_scrolled, true, true, 0);
        
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
}

