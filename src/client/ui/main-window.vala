/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MainWindow : Gtk.Window {
    private const int MESSAGE_LIST_WIDTH = 250;
    private const int FOLDER_LIST_WIDTH = 100;
    
    public FolderList folder_list { get; private set; default = new FolderList(); }
    public ConversationListStore conversation_list_store { get; private set; default = new ConversationListStore(); }
    public MainToolbar main_toolbar { get; private set; }
    public ConversationListView conversation_list_view  { get; private set; }
    public ConversationViewer conversation_viewer { get; private set; default = new ConversationViewer(); }
    
    private int window_width;
    private int window_height;
    private bool window_maximized;
    private Gtk.Paned folder_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    private Gtk.Paned conversations_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
    private Gtk.Spinner spinner = new Gtk.Spinner();
    private bool is_shown = false;
    
    public MainWindow() {
        title = GearyApplication.NAME;
        
        conversation_list_view = new ConversationListView(conversation_list_store);
        
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
        
        folder_paned.set_position(GearyApplication.instance.config.folder_list_pane_position);
        conversations_paned.set_position(GearyApplication.instance.config.messages_pane_position);
        
        base.show_all();
        is_shown = true;
    }
    
    public override void destroy() {
        if (is_shown) {
            // Save window dimensions.
            GearyApplication.instance.config.window_width = window_width;
            GearyApplication.instance.config.window_height = window_height;
            GearyApplication.instance.config.window_maximize = window_maximized;
            
            // Save pane positions.
            GearyApplication.instance.config.folder_list_pane_position = folder_paned.get_position();
            GearyApplication.instance.config.messages_pane_position = conversations_paned.get_position();
        }
        
        base.destroy();
    }
    
    private bool on_delete_event() {
        GearyApplication.instance.exit();
        
        return true;
    }
    
    public override bool configure_event(Gdk.EventConfigure event) {
        // Get window dimensions.
        window_maximized = (get_window().get_state() == Gdk.WindowState.MAXIMIZED);
        if (!window_maximized)
            get_size(out window_width, out window_height);
        
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
        Gtk.ScrolledWindow conversation_list_scrolled = new Gtk.ScrolledWindow(null, null);
        conversation_list_scrolled.set_size_request(MESSAGE_LIST_WIDTH, -1);
        conversation_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        conversation_list_scrolled.add(conversation_list_view);
        
        // Three-pane display.
        Gtk.Box status_bar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        Gtk.Statusbar status_bar = new Gtk.Statusbar();
        status_bar.add(spinner);
        status_bar_box.pack_start(folder_list_scrolled);
        status_bar_box.pack_start(status_bar, false, false, 0);
        get_style_context().add_class("sidebar-pane-separator");
        
         // Message list left of message viewer.
        conversations_paned.pack1(conversation_list_scrolled, false, false);
        conversations_paned.pack2(conversation_viewer.content_area, true, true);
        
        // Folder list to the left of everything.
        folder_paned.pack1(status_bar_box, false, false);
        folder_paned.pack2(conversations_paned, true, false);
        
        main_layout.pack_end(folder_paned, true, true, 0);
        
        add(main_layout);
    }
}

