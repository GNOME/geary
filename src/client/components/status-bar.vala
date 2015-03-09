/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A wrapper around Gtk.Statusbar that predefines messages and context areas so
 * you don't have to keep track of them elsewhere.  You can activate and
 * deactivate messages, instead of worrying about context areas and stacks.
 * Internally, activations are reference counted, and every new activation
 * pushes the message to the top of its context area's stack.  Only when
 * the number of deactivations equals the number of activations is the message
 * removed from the stack entirely.
 */
public class StatusBar : Gtk.Statusbar {
    public enum Message {
        OUTBOX_SENDING,
        OUTBOX_SEND_FAILURE,
        OUTBOX_SAVE_SENT_MAIL_FAILED;
        
        internal string get_text() {
            switch (this) {
                case Message.OUTBOX_SENDING:
                    /// Displayed in the space-limited status bar while a message is in the process of being sent.
                    return _("Sending...");
                case Message.OUTBOX_SEND_FAILURE:
                    /// Displayed in the space-limited status bar when a message fails to be sent due to error.
                    return _("Error sending email");
                case Message.OUTBOX_SAVE_SENT_MAIL_FAILED:
                    // Displayed in the space-limited status bar when a message fails to be uploaded
                    // to Sent Mail after being sent.
                    return _("Error saving sent mail");
                default:
                    assert_not_reached();
            }
        }
        
        internal Context get_context() {
            switch (this) {
                case Message.OUTBOX_SENDING:
                    return Context.OUTBOX;
                case Message.OUTBOX_SEND_FAILURE:
                    return Context.OUTBOX;
                case Message.OUTBOX_SAVE_SENT_MAIL_FAILED:
                    return Context.OUTBOX;
                default:
                    assert_not_reached();
            }
        }
    }
    
    internal enum Context {
        OUTBOX,
    }
    
    private Gee.HashMap<Context, uint> context_ids = new Gee.HashMap<Context, uint>();
    private Gee.HashMap<Message, uint> message_ids = new Gee.HashMap<Message, uint>();
    private Gee.HashMap<Message, int> message_counts = new Gee.HashMap<Message, int>();
    
    public StatusBar() {
        set_context_id(Context.OUTBOX);
    }
    
    private void set_context_id(Context context) {
        context_ids.set(context, get_context_id(context.to_string()));
    }
    
    private int get_count(Message message) {
        return (message_counts.has_key(message) ? message_counts.get(message) : 0);
    }
    
    private void push_message(Message message) {
        message_ids.set(message, push(context_ids.get(message.get_context()), message.get_text()));
    }
    
    private void remove_message(Message message) {
        remove(context_ids.get(message.get_context()), message_ids.get(message));
        message_ids.unset(message);
    }
    
    /**
     * Return whether the message has been activated more times than it has
     * been deactivated.
     */
    public bool is_message_active(Message message) {
        return message_ids.has_key(message);
    }
    
    public void activate_message(Message message) {
        if (is_message_active(message))
            remove_message(message);
        
        push_message(message);
        message_counts.set(message, get_count(message) + 1);
    }
    
    public void deactivate_message(Message message) {
        if (!is_message_active(message))
            return;
        
        int count = get_count(message);
        if (count == 1)
            remove_message(message);
        message_counts.set(message, count - 1);
    }
}
