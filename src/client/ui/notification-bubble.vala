/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Displays a notification bubble
public class NotificationBubble : GLib.Object {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.SUBJECT;
    
    private static Canberra.Context? sound_context = null;
    
    private Notify.Notification notification;
    private unowned List<string> caps;
    
    public NotificationBubble() {
        if (!Notify.is_initted()) {
            if (!Notify.init(GearyApplication.PRGNAME))
                critical("Failed to initialize libnotify.");
        }
        
        init_sound();
        caps = Notify.get_server_caps();
        
        // Avoid constructor due to ABI change
        notification = (Notify.Notification) GLib.Object.new(
            typeof (Notify.Notification),
            "icon-name", "geary",
            "summary", GLib.Environment.get_application_name());
        notification.set_hint_string("desktop-entry", "geary");
        if (caps.find("actions") != null)
            notification.add_action("default", _("Open"), on_default_action);
    }
    
    private static void init_sound() {
        if (sound_context == null)
            Canberra.Context.create(out sound_context);
    }
    
    private void on_default_action(Notify.Notification notification, string action) {
        GearyApplication.instance.activate(new string[0]);
    }

    public void notify_new_mail(int count) throws GLib.Error {
        if (!GearyApplication.instance.config.show_notifications)
            return;

        notification.set_category("email.arrived");
        
        prepare_notification(ngettext("%d new message", "%d new messages", count).printf(count),
           "message-new-email");
        notification.show();
    }

    public async void notify_one_message_async(Geary.Email email, GLib.Cancellable? cancellable) throws GLib.Error {
        assert(email.fields.fulfills(REQUIRED_FIELDS));

        if (!GearyApplication.instance.config.show_notifications)
            return;
        
        // possible to receive email with no originator
        Geary.RFC822.MailboxAddress? primary = email.get_primary_originator();
        if (primary == null) {
            notify_new_mail(1);
            
            return;
        }
        
        notification.set_category("email.arrived");
        notification.set("summary", primary.get_short_address());
        
        string message;
        if (email.fields.fulfills(Geary.Email.Field.PREVIEW)) {
            message = "%s %s".printf(email.get_subject_as_string(),
                Geary.String.reduce_whitespace(email.get_preview_as_string()));
        } else {
            message = email.get_subject_as_string();
        }
        
        prepare_notification(message, "message-new-email");
        
        File file = File.new_for_uri(Gravatar.get_image_uri(primary, Gravatar.Default.MYSTERY_MAN));
        try {
            InputStream stream = yield file.read_async(GLib.Priority.DEFAULT, cancellable);
            notification.set_image_from_pixbuf(
                yield Gdk.Pixbuf.new_from_stream_async(stream, cancellable));
        } catch (GLib.Error avatar_error) {
            debug("Failed to get avatar for notification: %s", avatar_error.message);
        }
        
        try {
            notification.show();
        } catch (GLib.Error error) {
            warning("Failed to show notification: %s", error.message);
        }
    }
    
    private void prepare_notification(string message, string sound) throws GLib.Error {
        notification.set("body", message);
        
        if (caps.find("sound") != null)
            notification.set_hint_string("sound-name", sound);
        else
            play_sound(sound);
        
    }
    
    public static void play_sound(string sound) {
        if (!GearyApplication.instance.config.play_sounds)
            return;
        init_sound();
        sound_context.play(0, Canberra.PROP_EVENT_ID, sound);
    }
}

