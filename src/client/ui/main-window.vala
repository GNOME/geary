/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MainWindow : Gtk.Window {
    private const int MESSAGE_LIST_WIDTH = 250;
    
    public FolderListStore folder_list_store { get; private set; default = new FolderListStore(); }
    public MessageListStore message_list_store { get; private set; default = new MessageListStore(); }
    public MainToolbar main_toolbar { get; private set; }
    public MessageListView message_list_view  { get; private set; }
    public FolderListView folder_list_view  { get; private set; }
    public MessageViewer message_viewer { get; private set; default = new MessageViewer(); }
    
    private int window_width;
    private int window_height;
    private bool window_maximized;
    private Gtk.HPaned folder_paned = new Gtk.HPaned();
    private Gtk.HPaned messages_paned = new Gtk.HPaned();
    private Gtk.Spinner spinner = new Gtk.Spinner();
    
    public MainWindow() {
        title = GearyApplication.NAME;
        
        message_list_view = new MessageListView(message_list_store);
        folder_list_view = new FolderListView(folder_list_store);
        
        add_accel_group(GearyApplication.instance.ui_manager.get_accel_group());
        
        create_layout();
    }
    
    public override void show_all() {
        set_default_size(GearyApplication.instance.config.window_width, 
            GearyApplication.instance.config.window_height);
        if (GearyApplication.instance.config.window_maximize)
            maximize();
        
        folder_paned.set_position(GearyApplication.instance.config.folder_list_pane_position);
        messages_paned.set_position(GearyApplication.instance.config.messages_pane_position);
        
        base.show_all();
    }
    
    public override void destroy() {
        // Save window dimensions.
        GearyApplication.instance.config.window_width = window_width;
        GearyApplication.instance.config.window_height = window_height;
        GearyApplication.instance.config.window_maximize = window_maximized;
        
        // Save pane positions.
        GearyApplication.instance.config.folder_list_pane_position = folder_paned.get_position();
        GearyApplication.instance.config.messages_pane_position = messages_paned.get_position();
        
        GearyApplication.instance.exit();
        
        base.destroy();
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
        folder_list_scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        folder_list_scrolled.add(folder_list_view);
        
        // message list
        Gtk.ScrolledWindow message_list_scrolled = new Gtk.ScrolledWindow(null, null);
        message_list_scrolled.set_size_request(MESSAGE_LIST_WIDTH, -1);
        message_list_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_list_scrolled.add(message_list_view);
        message_list_scrolled.resize_mode = Gtk.ResizeMode.IMMEDIATE;
        
        // message viewer
        Gtk.ScrolledWindow message_viewer_scrolled = new Gtk.ScrolledWindow(null, null);
        message_viewer_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_viewer_scrolled.add(message_viewer);
        
        // three-pane display: folder list on left and messages on right separated by grippable
        folder_paned.pack1(folder_list_scrolled, false, false);
        folder_paned.pack2(message_list_scrolled, true, false);
        
        Gtk.Box status_bar_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        Gtk.Statusbar status_bar = new Gtk.Statusbar();
        status_bar.add(spinner);
        status_bar_box.pack_start(folder_paned);
        status_bar_box.pack_start(status_bar, false, false, 0);
        
         // three-pane display: message list left of current message on bottom separated by
        // grippable
        messages_paned.pack1(status_bar_box, false, false);
        messages_paned.pack2(message_viewer_scrolled, true, true);
        
        main_layout.pack_end(messages_paned, true, true, 0);
        
        add(main_layout);
    }
}

