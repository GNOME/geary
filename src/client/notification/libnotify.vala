/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Displays a notification via libnotify
public class Libnotify : Geary.BaseObject {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.SUBJECT;
    
    private static Canberra.Context? sound_context = null;
    
    private NewMessagesMonitor monitor;
    private Notify.Notification? current_notification = null;
    private Geary.Folder? folder = null;
    private Geary.Email? email = null;
    private unowned List<string> caps;

    public signal void invoked(Geary.Folder? folder, Geary.Email? email);
    
    public Libnotify(NewMessagesMonitor monitor) {
        this.monitor = monitor;
        
        monitor.add_required_fields(REQUIRED_FIELDS);
        
        if (!Notify.is_initted()) {
            if (!Notify.init(GearyApplication.PRGNAME))
                message("Failed to initialize libnotify.");
        }
        
        init_sound();
        caps = Notify.get_server_caps();
        
        monitor.new_messages_arrived.connect(on_new_messages_arrived);
    }
    
    ~Libnotify() {
        monitor.new_messages_arrived.disconnect(on_new_messages_arrived);
    }
    
    private static void init_sound() {
        if (sound_context == null)
            Canberra.Context.create(out sound_context);
    }
    
    private void on_new_messages_arrived(Geary.Folder folder, int total, int added) {
        if (added == 1 && monitor.last_new_message_folder != null &&
            monitor.last_new_message != null) {
            notify_one_message_async.begin(monitor.last_new_message_folder,
                monitor.last_new_message, null);
        } else if (added > 0) {
            notify_new_mail(folder, added);
        }
    }
    
    private void on_default_action(Notify.Notification notification, string action) {
        invoked(folder, email);
        GearyApplication.instance.activate(new string[0]);
    }
    
    private void notify_new_mail(Geary.Folder folder, int added) {
        // don't pass email if invoked
        this.folder = null;
        email = null;
        
        if (!GearyApplication.instance.config.show_notifications ||
            !monitor.should_notify_new_messages(folder))
            return;
        
        string body = ngettext("%d new message", "%d new messages", added).printf(added);
        int total = monitor.get_new_message_count(folder);
        if (total > added) {
            body = ngettext("%s, %d new message total", "%s, %d new messages total", total).printf(
                body, total);
        }
        
        issue_notification(folder.account.information.email, body, null);
    }
    
    private async void notify_one_message_async(Geary.Folder folder, Geary.Email email,
        GLib.Cancellable? cancellable) throws GLib.Error {
        assert(email.fields.fulfills(REQUIRED_FIELDS));
        
        // used if notification is invoked
        this.folder = folder;
        this.email = email;
        
        if (!GearyApplication.instance.config.show_notifications ||
            !monitor.should_notify_new_messages(folder))
            return;
        
        // possible to receive email with no originator
        Geary.RFC822.MailboxAddress? primary = email.get_primary_originator();
        if (primary == null) {
            notify_new_mail(folder, 1);
            
            return;
        }
        
        string body;
        int count = monitor.get_new_message_count(folder);
        if (count <= 1) {
            body = email.get_subject_as_string();
        } else {
            body = ngettext("%s\n(%d new message for %s)", "%s\n(%d new messages for %s)", count).printf(
                email.get_subject_as_string(), count, folder.account.information.email);
        }
        
        // get the avatar
        Gdk.Pixbuf? avatar = null;
        InputStream? ins = null;
        File file = File.new_for_uri(Gravatar.get_image_uri(primary, Gravatar.Default.MYSTERY_MAN));
        try {
            ins = yield file.read_async(GLib.Priority.DEFAULT, cancellable);
            avatar = yield new Gdk.Pixbuf.from_stream_async(ins, cancellable);
        } catch (Error err) {
            debug("Failed to get avatar for notification: %s", err.message);
        }
        
        if (ins != null) {
            try {
                yield ins.close_async(Priority.DEFAULT, cancellable);
            } catch (Error close_err) {
                // ignored
            }
            
            ins = null;
        }
        
        issue_notification(primary.get_short_address(), body, avatar);
    }
    
    private void issue_notification(string summary, string body, Gdk.Pixbuf? icon) {
        // only one outstanding notification at a time
        if (current_notification != null) {
            try {
                current_notification.close();
            } catch (Error err) {
                debug("Unable to close current libnotify notification: %s", err.message);
            }
            
            current_notification = null;
        }
        
        // Avoid constructor due to ABI change
        current_notification = (Notify.Notification) GLib.Object.new(
            typeof (Notify.Notification),
            "icon-name", "geary",
            "summary", GLib.Environment.get_application_name());
        current_notification.set_hint_string("desktop-entry", "geary");
        if (caps.find_custom("actions", GLib.strcmp) != null)
            current_notification.add_action("default", _("Open"), on_default_action);
        
        current_notification.set_category("email.arrived");
        current_notification.set("summary", summary);
        current_notification.set("body", body);
        
        if (icon != null)
            current_notification.set_image_from_pixbuf(icon);
        
        if (caps.find("sound") != null)
            current_notification.set_hint_string("sound-name", "message-new-email");
        else
            play_sound("message-new-email");
        
        try {
            current_notification.show();
        } catch (Error err) {
            message("Unable to show notification: %s", err.message);
        }
    }
    
    public static void play_sound(string sound) {
        if (!GearyApplication.instance.config.play_sounds)
            return;
        
        init_sound();
        sound_context.play(0, Canberra.PROP_EVENT_ID, sound);
    }
}

