/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Displays a notification via GLibNotification
public class GLibNotification : Geary.BaseObject {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.SUBJECT;

    private static Canberra.Context? sound_context = null;

    private weak NewMessagesMonitor monitor;
    private GLib.Notification? current_notification = null;
    private GLib.Notification? error_notification = null;
    private Geary.Folder? folder = null;
    private Geary.Email? email = null;


    public GLibNotification(NewMessagesMonitor monitor) {
        this.monitor = monitor;
        init_sound();

        this.monitor.add_required_fields(REQUIRED_FIELDS);
        this.monitor.new_messages_arrived.connect(on_new_messages_arrived);
    }

    ~GLibNotification() {
        this.monitor.new_messages_arrived.disconnect(on_new_messages_arrived);
    }

    private static void init_sound() {
        if (sound_context == null)
            Canberra.Context.create(out sound_context);
    }

    private void on_new_messages_arrived(Geary.Folder folder, int total, int added) {
        if (added == 1 && monitor.last_new_message_folder != null &&
            monitor.last_new_message != null) {
            notify_one_message_async.begin(
                monitor.last_new_message_folder,
                monitor.last_new_message,
                null
            );
        } else if (added > 0) {
            notify_new_mail(folder, added);
        }
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

        issue_current_notification(folder.account.information.display_name, body, null);
    }

    private async void notify_one_message_async(Geary.Folder folder,
                                                Geary.Email email,
                                                GLib.Cancellable? cancellable) throws GLib.Error {
        // used if notification is invoked
        this.folder = folder;
        this.email = email;

        if (!GearyApplication.instance.config.show_notifications ||
            !monitor.should_notify_new_messages(folder))
            return;

        Geary.RFC822.MailboxAddress? originator =
            Util.Email.get_primary_originator(email);
        if (originator != null) {
            Application.ContactStore contacts =
                this.monitor.get_contact_store(folder.account);
            Application.Contact contact = yield contacts.load(
                originator, cancellable
            );

            string body;
            int count = monitor.get_new_message_count(folder);
            if (count <= 1) {
                body = Util.Email.strip_subject_prefixes(email);
            } else {
                body = ngettext(
                    "%s\n(%d other new message for %s)",
                    "%s\n(%d other new messages for %s)", count - 1).printf(
                        Util.Email.strip_subject_prefixes(email),
                        count - 1,
                        folder.account.information.display_name
                    );
            }

            Gdk.Pixbuf? avatar = yield this.monitor.avatars.load(
                contact,
                originator,
                Application.AvatarStore.PIXEL_SIZE,
                cancellable
            );

            issue_current_notification(
                contact.is_trusted
                    ? contact.display_name : originator.to_short_display(),
                body,
                avatar
            );
        } else {
            notify_new_mail(folder, 1);
        }
    }

    private void issue_current_notification(string summary, string body, Gdk.Pixbuf? icon) {
        // only one outstanding notification at a time
        if (current_notification != null) {
            GearyApplication.instance.withdraw_notification("email.arrived");
            current_notification = null;
        }

        current_notification = issue_notification("email.arrived", summary, body, icon, "message-new_email");

    }

    private GLib.Notification issue_notification(string id, string summary, string body,
        Gdk.Pixbuf? icon, string? sound) {
        GLib.Notification notification = new GLib.Notification(summary);
        notification.set_body(body);
        //notification.set_default_action("app.activate");

        if (icon != null)
            notification.set_icon(icon);

        if (sound != null) {
            play_sound(sound);
        }

        GearyApplication.instance.send_notification(id, notification);

        return notification;
    }

    public static void play_sound(string sound) {
        if (!GearyApplication.instance.config.play_sounds)
            return;

        init_sound();
        sound_context.play(0, Canberra.PROP_EVENT_ID, sound);
    }

    public void set_error_notification(string summary, string body) {
        // Only one error at a time, guys.  (This means subsequent errors will
        // be dropped.  Since this is only used for one thing now, that's ok,
        // but it means in the future, a more robust system will be needed.)
        if (error_notification != null)
            return;

        error_notification = issue_notification("error", summary, body, null, null);
    }

    public void clear_error_notification() {
        GearyApplication.instance.withdraw_notification("error");
        error_notification = null;
    }
}
