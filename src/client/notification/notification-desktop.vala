/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Manages standard desktop application notifications.
 */
public class Notification.Desktop : Geary.BaseObject {


    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.ORIGINATORS | Geary.Email.Field.SUBJECT;

    private const string ARRIVED_ID = "email-arrived";
    private const string ERROR_ID = "error";


    private static void init_sound() {
        if (Desktop.sound_context == null) {
            Canberra.Context.create(out sound_context);
        }
    }

    private static Canberra.Context? sound_context = null;

    private weak NewMessagesMonitor monitor;
    private weak GearyApplication application;
    private GLib.Notification? current_notification = null;
    private GLib.Notification? error_notification = null;
    private Geary.Folder? folder = null;
    private Geary.Email? email = null;
    private GLib.Cancellable load_cancellable;


    public Desktop(NewMessagesMonitor monitor,
                   GearyApplication application,
                   GLib.Cancellable load_cancellable) {
        this.monitor = monitor;
        this.application = application;
        this.load_cancellable = load_cancellable;
        init_sound();

        this.monitor.add_required_fields(REQUIRED_FIELDS);
        this.monitor.new_messages_arrived.connect(on_new_messages_arrived);
    }

    ~Desktop() {
        this.load_cancellable.cancel();
        this.monitor.new_messages_arrived.disconnect(on_new_messages_arrived);
    }

    public void play_sound(string sound) {
        if (this.application.config.play_sounds) {
            Desktop.sound_context.play(
                0, Canberra.PROP_EVENT_ID, sound
            );
        }
    }

    public void clear_arrived_notification() {
        this.application.withdraw_notification(ARRIVED_ID);
        this.current_notification = null;
    }

    public void set_error_notification(string summary, string body) {
        // Only one error at a time, guys.  (This means subsequent errors will
        // be dropped.  Since this is only used for one thing now, that's ok,
        // but it means in the future, a more robust system will be needed.)
        if (this.error_notification == null) {
            this.error_notification = issue_notification(
                ERROR_ID, summary, body, null
            );
        }
    }

    public void clear_error_notification() {
        this.error_notification = null;
        this.application.withdraw_notification(ERROR_ID);
    }

    private void on_new_messages_arrived(Geary.Folder folder,
                                         int total,
                                         int added) {
        if (added == 1 &&
            monitor.last_new_message_folder != null &&
            monitor.last_new_message != null) {
            this.notify_one_message.begin(
                monitor.last_new_message_folder,
                monitor.last_new_message,
                this.load_cancellable
            );
        } else if (added > 0) {
            notify_new_mail(folder, added);
        }
    }

    private void notify_new_mail(Geary.Folder folder, int added) {
        // don't pass email if invoked
        this.folder = null;
        this.email = null;

        if (this.application.config.show_notifications &&
            this.monitor.should_notify_new_messages(folder)) {
            string body = ngettext(
                /// Notification body text for new email when no other
                /// new messages are already awaiting.
                "%d new message", "%d new messages", added
            ).printf(added);
            int total = monitor.get_new_message_count(folder);
            if (total > added) {
                body = ngettext(
                    /// Notification body text for new email when
                    /// other new messages have already been notified
                    /// about
                    "%s, %d new message total", "%s, %d new messages total",
                    total
                ).printf(body, total);
            }

            issue_current_notification(
                this.folder.account.information.display_name, body
            );
        }
    }

    private async void notify_one_message(Geary.Folder folder,
                                          Geary.Email email,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error {
        // used if notification is invoked
        this.folder = folder;
        this.email = email;

        Geary.RFC822.MailboxAddress? originator =
            Util.Email.get_primary_originator(email);
        if (this.application.config.show_notifications &&
            this.monitor.should_notify_new_messages(folder) &&
            originator != null) {
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

            issue_current_notification(
                contact.is_trusted
                    ? contact.display_name : originator.to_short_display(),
                body
            );
        } else {
            notify_new_mail(folder, 1);
        }
    }

    private void issue_current_notification(string summary, string body) {
        // only one outstanding notification at a time
        clear_arrived_notification();
        this.current_notification = issue_notification(
            ARRIVED_ID, summary, body, "message-new_email"
        );
    }

    private GLib.Notification issue_notification(string id,
                                                 string summary,
                                                 string body,
                                                 string? sound) {
        GLib.Notification notification = new GLib.Notification(summary);
        notification.set_body(body);
        notification.set_icon(
            new GLib.ThemedIcon("%s-symbolic".printf(GearyApplication.APP_ID))
        );
        //notification.set_default_action("app.activate");

        if (sound != null) {
            play_sound(sound);
        }

        this.application.send_notification(id, notification);
        return notification;
    }

}
