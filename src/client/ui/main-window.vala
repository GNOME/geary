/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MainWindow : Gtk.Window {
    private const int MESSAGE_LIST_WIDTH = 250;
    private const int FETCH_EMAIL_CHUNK_COUNT = 50;
    
    private MainToolbar main_toolbar;
    private MessageListStore message_list_store = new MessageListStore();
    private MessageListView message_list_view;
    private FolderListStore folder_list_store = new FolderListStore();
    private FolderListView folder_list_view;
    private MessageViewer message_viewer = new MessageViewer();
    private Geary.EngineAccount? account = null;
    private Geary.Folder? current_folder = null;
    private bool second_list_pass_required = false;
    private int window_width;
    private int window_height;
    private bool window_maximized;
    private Gtk.HPaned folder_paned = new Gtk.HPaned();
    private Gtk.HPaned messages_paned = new Gtk.HPaned();
    private Cancellable cancellable = new Cancellable();
    
    public MainWindow() {
        title = GearyApplication.NAME;
        
        message_list_view = new MessageListView(message_list_store);
        message_list_view.message_selected.connect(on_message_selected);
        
        folder_list_view = new FolderListView(folder_list_store);
        folder_list_view.folder_selected.connect(on_folder_selected);
        
        add_accel_group(GearyApplication.instance.ui_manager.get_accel_group());
        
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
            warning("%s", err.message);
        }
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
    
    private void create_layout() {
        Gtk.VBox main_layout = new Gtk.VBox(false, 0);
        
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
        
        // message viewer
        Gtk.ScrolledWindow message_viewer_scrolled = new Gtk.ScrolledWindow(null, null);
        message_viewer_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        message_viewer_scrolled.add_with_viewport(message_viewer);
        
        // three-pane display: message list left of current message on bottom separated by
        // grippable
        messages_paned.pack1(message_list_scrolled, false, false);
        messages_paned.pack2(message_viewer_scrolled, true, false);
        
        // three-pane display: folder list on left and messages on right separated by grippable
        folder_paned.pack1(folder_list_scrolled, false, false);
        folder_paned.pack2(messages_paned, true, false);
        
        main_layout.pack_end(folder_paned, true, true, 0);
        
        add(main_layout);
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
        cancel();
        message_list_store.clear();
        
        if (current_folder != null) {
            current_folder.messages_appended.disconnect(on_folder_messages_appended);
            yield current_folder.close_async();
        }
        
        current_folder = folder;
        current_folder.messages_appended.connect(on_folder_messages_appended);
        
        yield current_folder.open_async(true, cancellable);
        
        // Do a quick-list of the messages (which should return what's in the local store) if
        // supported by the Folder, followed by a complete list if needed
        second_list_pass_required =
            current_folder.get_supported_list_flags().is_all_set(Geary.Folder.ListFlags.FAST);
        current_folder.lazy_list_email(-1, FETCH_EMAIL_CHUNK_COUNT, MessageListStore.REQUIRED_FIELDS,
            current_folder.get_supported_list_flags() & Geary.Folder.ListFlags.FAST,
            on_list_email_ready, cancellable);
    }
    
    private void on_list_email_ready(Gee.List<Geary.Email>? email, Error? err) {
        if (email != null && email.size > 0) {
            debug("Listing %d emails", email.size);
            foreach (Geary.Email envelope in email) {
                if (!message_list_store.has_envelope(envelope))
                    message_list_store.append_envelope(envelope);
            }
        }
        
        if (err != null) {
            debug("Error while listing email: %s", err.message);
            
            // TODO: Better error handling here
            return;
        }
        
        // end of list, go get the previews for them
        if (email == null)
            do_fetch_previews.begin(cancellable);
    }
    
    private async void do_fetch_previews(Cancellable? cancellable) throws Error {
        int count = message_list_store.get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Email? email = message_list_store.get_message_at_index(ctr);
            Geary.Email? body = yield current_folder.fetch_email_async(email.id,
                Geary.Email.Field.HEADER | Geary.Email.Field.BODY | Geary.Email.Field.ENVELOPE | 
                Geary.Email.Field.PROPERTIES, cancellable);
            message_list_store.set_preview_at_index(ctr, body);
        }
        
        // with all the previews fetched, now go back and do a full list (if required)
        if (second_list_pass_required) {
            second_list_pass_required = false;
            debug("Doing second list pass now");
            current_folder.lazy_list_email(-1, FETCH_EMAIL_CHUNK_COUNT, MessageListStore.REQUIRED_FIELDS,
                Geary.Folder.ListFlags.NONE, on_list_email_ready, cancellable);
        }
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
    
    private void on_message_selected(Geary.Email? email) {
        if (email != null)
            do_select_message.begin(email, on_select_message_completed);
    }
    
    private async void do_select_message(Geary.Email email) throws Error {
        if (current_folder == null) {
            debug("Message %s selected with no folder selected", email.to_string());
            
            return;
        }
        
        debug("Fetching email %s", email.to_string());
        
        Geary.Email full_email = yield current_folder.fetch_email_async(email.id,
            MessageViewer.REQUIRED_FIELDS, cancellable);
        
        message_viewer.clear();
        message_viewer.add_message(full_email);
    }
    
    private void on_select_message_completed(Object? source, AsyncResult result) {
        try {
            do_select_message.end(result);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
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
    
    private void on_folder_messages_appended() {
        int high = message_list_store.get_highest_folder_position();
        if (high < 0) {
            debug("Unable to find highest message position in %s", current_folder.to_string());
            
            return;
        }
        
        debug("Message(s) appended to %s, fetching email at %d and above", current_folder.to_string(),
            high + 1);
        
        // Want to get the one *after* the highest position in the message list
        current_folder.lazy_list_email(high + 1, -1, MessageListStore.REQUIRED_FIELDS,
            Geary.Folder.ListFlags.NONE, on_list_email_ready, cancellable);
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
    
    private void cancel() {
        Cancellable old_cancellable = cancellable;
        cancellable = new Cancellable();
        
        old_cancellable.cancel();
    }
}

