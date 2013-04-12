/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class MainWindow : Gtk.Window {
    private const int MESSAGE_LIST_WIDTH = 250;
    private const int FOLDER_LIST_WIDTH = 100;
    
    public FolderList.Tree folder_list { get; private set; default = new FolderList.Tree(); }
    public ConversationListStore conversation_list_store { get; private set; default = new ConversationListStore(); }
    public MainToolbar main_toolbar { get; private set; }
    public ConversationListView conversation_list_view  { get; private set; }
    public ConversationViewer conversation_viewer { get; private set; default = new ConversationViewer(); }
    
    public int window_width { get; set; }
    public int window_height { get; set; }
    public bool window_maximized { get; set; }

    private Gtk.Paned folder_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    private Gtk.Paned conversations_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    
    private Gtk.ScrolledWindow conversation_list_scrolled;
    private Gtk.Spinner spinner = new Gtk.Spinner();
    
    public MainWindow() {
        title = GearyApplication.NAME;
        
        conversation_list_view = new ConversationListView(conversation_list_store);
        
        // This code both loads AND saves the pane positions with live
        // updating. This is more resilient against crashes because
        // the value in dconf changes *immediately*, and stays saved
        // in the event of a crash.
        Configuration config = GearyApplication.instance.config;
        config.bind(Configuration.FOLDER_LIST_PANE_POSITION_NAME, folder_paned, "position");
        config.bind(Configuration.MESSAGES_PANE_POSITION_NAME, conversations_paned, "position");
        config.bind(Configuration.WINDOW_WIDTH_NAME, this, "window-width");
        config.bind(Configuration.WINDOW_HEIGHT_NAME, this, "window-height");
        config.bind(Configuration.WINDOW_MAXIMIZE_NAME, this, "window-maximized");
        
        add_accel_group(GearyApplication.instance.ui_manager.get_accel_group());
        
        GLib.List<Gdk.Pixbuf> pixbuf_list = new GLib.List<Gdk.Pixbuf>();
        pixbuf_list.append(IconFactory.instance.application_icon);
        set_default_icon_list(pixbuf_list);
        
        delete_event.connect(on_delete_event);
        
        create_layout();
    }
    
    public override void show_all() {
        set_default_size(GearyApplication.instance.config.window_width, 
            GearyApplication.instance.config.window_height);
        if (GearyApplication.instance.config.window_maximize)
            maximize();
        
        base.show_all();
    }
    
    private bool on_delete_event() {
        GearyApplication.instance.exit();
        
        return true;
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        // Get window dimensions.
        window_maximized = (get_window().get_state() == Gdk.WindowState.MAXIMIZED);
        if (!window_maximized) {
            int width, height;
            get_size(out width, out height);
            
            // can't use properties as out variables
            window_width = width;
            window_height = height;
        }
        
        return base.configure_event(event);
    }
    
    // Displays or stops displaying busy spinner.
    public void set_busy(bool is_busy) {
        if (is_busy) {
            spinner.start();
            spinner.show();
        } else {
            spinner.stop();
            spinner.hide();
        }
    }
    
    private void create_layout() {
        Gtk.Box main_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        
        // Toolbar.
        main_toolbar = new MainToolbar();
        main_layout.pack_start(main_toolbar, false, false, 0);
        
        // folder list
        Gtk.ScrolledWindow folder_list_scrolled = new Gtk.ScrolledWindow(null, null);
        folder_list_scrolled.set_size_request(FOLDER_LIST_WIDTH, -1);
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add(folder_list);
        
        // message list
        conversation_list_scrolled = new Gtk.ScrolledWindow(null, null);
        conversation_list_scrolled.set_size_request(MESSAGE_LIST_WIDTH, -1);
        conversation_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        conversation_list_scrolled.add(conversation_list_view);
        
        // Three-pane display.
        Gtk.Box status_bar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        Gtk.Statusbar status_bar = new Gtk.Statusbar();
        status_bar.add(spinner);
        status_bar_box.pack_start(folder_list_scrolled);
        status_bar_box.pack_start(status_bar, false, false, 0);
        
#if !HAVE_LIBGRANITE
        folder_paned.get_style_context().add_class("sidebar-pane-separator");
#endif
        
         // Message list left of message viewer.
        conversations_paned.pack1(conversation_list_scrolled, false, false);
        conversations_paned.pack2(conversation_viewer, true, true);
        
        // Folder list to the left of everything.
        folder_paned.pack1(status_bar_box, false, false);
        folder_paned.pack2(conversations_paned, true, false);
        
        main_layout.pack_end(folder_paned, true, true, 0);
        
        add(main_layout);
    }
    
    // Returns true when there's a conversation list scrollbar visible, i.e. the list is tall
    // enough to need one.  Otherwise returns false.
    public bool conversation_list_has_scrollbar() {
        Gtk.Scrollbar? scrollbar = conversation_list_scrolled.get_vscrollbar() as Gtk.Scrollbar;
        return scrollbar != null && scrollbar.get_visible();
    }
}

