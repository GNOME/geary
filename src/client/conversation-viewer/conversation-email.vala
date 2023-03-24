/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016,2019 Michael Gratton <mike@vee.net>
 * Copyright 2023 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an email in a conversation.
 *
 * This view corresponds to {@link Geary.Email}, displaying the
 * email's primary message (a {@link Geary.RFC822.Message}), any
 * sub-messages (also instances of {@link Geary.RFC822.Message}) and
 * attachments. The RFC822 messages are themselves displayed by {@link
 * ConversationMessage}.
 */
public class ConversationEmail : Geary.BaseInterface {

    private const string MANUAL_READ_CLASS = "geary-manual-read";
    private const string SENT_CLASS = "geary-sent";
    private const string STARRED_CLASS = "geary-starred";
    private const string UNREAD_CLASS = "geary-unread";
    private const string REPLACED_CID_TEMPLATE = "replaced_%02u@geary";
    private const string REPLACED_IMAGE_CLASS = "geary_replaced_inline_image";
    private const string MESSAGE_ENABLE_REMOTE_LOAD = "__enable_remote_load__";

    /** Fields that must be available for constructing the view. */
    internal const Geary.Email.Field REQUIRED_FOR_CONSTRUCT = (
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.PREVIEW |
        Geary.Email.Field.FLAGS
    );

    /** Fields that must be available for loading the body. */
    internal const Geary.Email.Field REQUIRED_FOR_LOAD = (
        // Include those needed by the constructor since we'll replace
        // the ctor's email arg value once the body has been fully
        // loaded
        REQUIRED_FOR_CONSTRUCT |
        Geary.Email.REQUIRED_FOR_MESSAGE
    );

     /** Contact for the primary originator, if any. */
    internal Application.Contact? primary_contact {
        get; private set;
    }

    public Geary.Email email { get; private set; }

    public Geary.App.Conversation conversation;

    /** Specifies the loading state for a message part. */
    public enum LoadState {

        /** Loading has not started. */
        NOT_STARTED,

        /** Loading has started, but not completed. */
        STARTED,

        /** Loading has started and completed. */
        COMPLETED,

        /** Loading has started but encountered an error. */
        FAILED,

        /** Loading is not possible because we are offline */
        OFFLINE;

    }

     /** Determines the message body loading state. */
    public LoadState message_body_state { get; private set; default = NOT_STARTED; }

    private ConversationWebView web_view;

    // Store from which to load message content, if needed
    private Geary.App.EmailStore email_store;

    // Store from which to lookup contacts
    private Application.ContactStore contacts;

    private Application.Configuration config;

    private int next_replaced_buffer_number = 0;

    /**
     * Constructs a new view to display an email.
     *
     * This method sets up most of the user interface for displaying
     * the complete email, but does not attempt any possibly
     * long-running loading processes.
     */
    public ConversationEmail(ConversationWebView web_view,
                             Geary.App.Conversation conversation,
                             Geary.Email email,
                             Geary.App.EmailStore email_store,
                             Application.ContactStore contacts,
                             Application.Configuration config,
                             bool is_sent,
                             bool is_draft) {
        base_ref();
        this.web_view = web_view;
        this.conversation = conversation;
        this.email = email;
        //this.is_draft = is_draft;
        this.email_store = email_store;
        this.contacts = contacts;
        this.config = config;

        if (email.load_remote_images().is_certain()) {
            load_remote_resources.begin(email.id.hash());
        }
    }

    ~ConversationEmail() {
        base_unref();
    }

    public async void add(GLib.Cancellable load_cancellable) throws GLib.Error {
        string? display_name = null;
        string? address = null;

        yield load_primary_originator(load_cancellable);
        if (this.primary_contact != null) {
            display_name = this.primary_contact.display_name;
            foreach (Geary.RFC822.MailboxAddress _address in this.primary_contact.email_addresses) {
                address = _address.address;
                if (this.email.from.contains_normalized(_address.address)) {
                    break;
                }
            }
        }
        yield this.web_view.call_void(
            Util.JS.callable(
                "conversation_email.add"
            ).int((int) this.email.id.hash())
             .string(display_name)
             .string(address)
             .string_array(
                get_addresses(
                    this.email.from,
                    new Geary.RFC822.MailboxAddresses(
                        this.primary_contact.email_addresses)))
             .string_array(get_addresses(this.email.to, null))
             .string_array(get_addresses(this.email.cc, null))
             .string_array(get_addresses(this.email.bcc, null))
             .string(this.email.get_preview_as_string())
            , load_cancellable
        );
    }

    public async string? get_body(GLib.Cancellable load_cancellable) {
        yield this.load_body(load_cancellable);
        yield this.load_attachments(load_cancellable);

        switch (this.message_body_state) {
        case COMPLETED:
            Geary.RFC822.Message message = this.email.get_message();
            if (message.has_html_body()) {
                return message.get_html_body(inline_image_replacer);
            } else {
                return message.get_plain_body(true, inline_image_replacer);
            }
        case OFFLINE:
            return "OFFLINE";
        case FAILED:
            return "FAILED";
        default:
            return null;
        }
    }

    private async void load_primary_originator(GLib.Cancellable load_cancellable)
        throws GLib.Error {
        var primary_originator = Util.Email.get_primary_originator(this.email);
        if (primary_originator != null) {
            this.primary_contact = yield this.contacts.load(
                primary_originator, load_cancellable
            );
        }
    }

    private inline string get_address_str(Geary.RFC822.MailboxAddress address) {
        if (address.name == null) {
            return address.address;
        } else {
            return "%s <%s>".printf(address.name, address.address);
        }
    }

    private string[] get_addresses(Geary.RFC822.MailboxAddresses? rfc822_addresses,
                                   Geary.RFC822.MailboxAddresses? ignore) {
        GLib.Array<string> addresses = new GLib.Array<string>();
        if (rfc822_addresses != null) {
            foreach (Geary.RFC822.MailboxAddress address in rfc822_addresses) {
                if (ignore == null || !ignore.contains_normalized(address.address)) {
                    addresses.append_val(get_address_str(address));
                }
            }
        }
        return addresses.data;
    }

    private string[] get_reply_addresses(Geary.RFC822.MailboxAddresses? from,
                                         Geary.RFC822.MailboxAddresses? reply_to) {
        GLib.Array<string> addresses = new GLib.Array<string>();
        // Show any Reply-To header addresses if present, but only if
        // each is not already in the From header.
        if (reply_to != null) {
            foreach (Geary.RFC822.MailboxAddress address in reply_to) {
                if (from == null || !from.contains_normalized(address.address)) {
                    addresses.append_val(get_address_str(address));
                }
            }
        }
        return addresses.data;
    }

    private inline bool is_online() {
        return (this.email_store.account.incoming.current_status == CONNECTED);
    }

     /**
     * Loads the message body and attachments.
     *
     * This potentially hits the database if the email that the view
     * was constructed from doesn't satisfy requirements, loads
     * attachments, including views and avatars for any attached
     * messages, and waits for the primary message body content to
     * have been loaded by its web view before returning.
     */
    private async void load_body(GLib.Cancellable load_cancellable) {
        // Ensure we have required data to load the message
        bool loaded = this.email.fields.fulfills(REQUIRED_FOR_LOAD);

        if (loaded) {
            this.message_body_state = COMPLETED;
            return;
        }

        this.message_body_state = STARTED;
        try {
            this.email = yield this.email_store.fetch_email_async(
                this.email.id,
                REQUIRED_FOR_LOAD,
                LOCAL_ONLY, // Throws an error if not downloaded
                load_cancellable
            );
            this.message_body_state = COMPLETED;
        } catch (Geary.EngineError.INCOMPLETE_MESSAGE err) {
            // Don't have the complete message at the moment, so
            // download it in the background. Don't reset the body
            // load timeout here since this will attempt to fetch
            // from the remote
            if (is_online()) {
                yield this.fetch_remote_body(load_cancellable);
            } else {
                this.message_body_state = OFFLINE;
            }
        } catch (GLib.IOError.CANCELLED err) {
            debug("Loading email body cancelled");
        } catch (GLib.Error err) {
            this.message_body_state = FAILED;
        }
    }

    private async void load_attachments(GLib.Cancellable load_cancellable) {
        Gee.Map<string,Geary.Memory.Buffer> cid_resources =
            new Gee.HashMap<string,Geary.Memory.Buffer>();
        foreach (Geary.Attachment attachment in this.email.attachments) {
            // Assume all parts are attachments. As the primary and
            // secondary message bodies are loaded, any displayed
            // inline will be removed from the list.
            // this.displayed_attachments.add(attachment);

            if (attachment.content_id != null) {
                try {
                    cid_resources[attachment.content_id] =
                        new Geary.Memory.FileBuffer(attachment.file, true);
                } catch (Error err) {
                    debug("Could not open attachment: %s", err.message);
                }
            }
        }

        this.web_view.add_internal_resources(cid_resources);

    }

     private async void fetch_remote_body(GLib.Cancellable load_cancellable) {
        Geary.Email? email = null;

        try {
            debug("Downloading remote message: %s", this.email.to_string());
            email = yield this.email_store.fetch_email_async(
                this.email.id,
                REQUIRED_FOR_LOAD,
                FORCE_UPDATE,
                load_cancellable
            );

            if (email != null && !load_cancellable.is_cancelled()) {
                this.email = email;
            }
        } catch (GLib.Error err) {
            this.message_body_state = FAILED;
        }
    }

    // This delegate is called from within
    // Geary.RFC822.Message.get_body while assembling the plain or
    // HTML document when a non-text MIME part is encountered within a
    // multipart/mixed container.  If this returns null, the MIME part
    // is dropped from the final returned document; otherwise, this
    // returns HTML that is placed into the document in the position
    // where the MIME part was found
    private string? inline_image_replacer(Geary.RFC822.Part part) {
        Geary.Mime.ContentType content_type = part.content_type;
        if (content_type.media_type != "image" ||
            !this.web_view.can_show_mime_type(content_type.to_string())) {
            debug("Not displaying %s inline: unsupported Content-Type",
                  content_type.to_string());
            return null;
        }

        string? id = part.content_id;
        if (id == null) {
            id = REPLACED_CID_TEMPLATE.printf(this.next_replaced_buffer_number++);
        }

        try {
            this.web_view.add_internal_resource(
                id,
                part.write_to_buffer(Geary.RFC822.Part.EncodingConversion.UTF8)
            );
        } catch (Geary.RFC822.Error err) {
            debug("Failed to get inline buffer: %s", err.message);
            return null;
        }

        // Translators: This string is used as the HTML IMG ALT
        // attribute value when displaying an inline image in an email
        // that did not specify a file name. E.g. <IMG ALT="Image" ...
        string UNKNOWN_FILENAME_ALT_TEXT = _("Image");
        string clean_filename = Geary.HTML.escape_markup(
            part.get_clean_filename() ?? UNKNOWN_FILENAME_ALT_TEXT
        );

        return "<img alt=\"%s\" class=\"%s\" src=\"%s%s\" />".printf(
            clean_filename,
            REPLACED_IMAGE_CLASS,
            Components.WebView.CID_URL_PREFIX,
            Geary.HTML.escape_markup(id)
        );
    }

    private async void load_remote_resources(uint email_id)
        throws GLib.Error {
        yield this.web_view.call_void(
            Util.JS.callable(MESSAGE_ENABLE_REMOTE_LOAD).int(
                (int) this.email.id.hash()), null
        );
    }
}
