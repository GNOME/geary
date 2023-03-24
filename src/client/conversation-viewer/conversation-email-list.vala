/*
 * Copyright 2022 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying conversations as a list of emails.
 *
 * The view displays the current selected {@link
 * Geary.App.Conversation} from the conversation list. To do so, it
 * listens to signals from both the list and the current conversation
 * monitor, updating the email list as needed.
 *
 * Unlike ConversationEmailListStore (which sorts by date received),
 * ConversationEmailList sorts by the {@link Geary.Email.date} field
 * (the Date: header), as that's the date displayed to the user.
 */
public class ConversationEmailList : ConversationWebView {

    /** Fields that must be available for listing conversation email. */
    public const Geary.Email.Field REQUIRED_FIELDS = (
        // Sorting the conversation
        Geary.Email.Field.DATE |
        // Determine unread/starred, etc
        Geary.Email.Field.FLAGS |
        // Determine if the message is from the sender or not
        Geary.Email.Field.ORIGINATORS
    );

    /** Conversation being displayed. */
    public Geary.App.Conversation? conversation { get; private set; default=null;}

    private Application.Configuration config;

    // Used to load messages in conversation.
    private Geary.App.EmailStore? email_store = null;

    // Store from which to lookup contacts
    private Application.ContactStore? contacts = null;

    // Primary email address
    Geary.RFC822.MailboxAddress? primary_address = null;

    // Action related to current view
    private ConversationEmailListActions? actions = null;

    private GLib.Cancellable? load_cancellable = null;

    private GLib.Array<ConversationEmail> conversation_emails =
                                        new GLib.Array<ConversationEmail>();

    /**
     * Constructs a new conversation list instance.
     */
    public ConversationEmailList(Application.Configuration config) {
        base(config);
        this.config = config;
        this.actions = new ConversationEmailListActions(this, config);
        this.images_policy_clicked.connect(on_images_policy_clicked);
    }

    public async void load_conversation(Geary.App.Conversation conversation,
                                        Geary.App.EmailStore email_store,
                                        Application.ContactStore contacts,
                                        bool suppress_mark_timer,
                                        Gee.Collection<Geary.EmailIdentifier> scroll_to,
                                        GLib.Cancellable load_cancellable,
                                        Geary.SearchQuery? query)
        throws GLib.Error {
        this.conversation = conversation;
        this.email_store = email_store;
        this.contacts = contacts;
        this.load_cancellable = load_cancellable;
        this.conversation_emails.set_size(0);

        clear_internal_resources();

        Gee.Collection<Geary.Email>? emails = conversation.get_emails(
            Geary.App.Conversation.Ordering.SENT_DATE_DESCENDING
        );

        if (emails.size > 0) {
            var e_arr = emails.to_array();
            var subject = e_arr[e_arr.length - 1].subject.value;
            this.primary_address = e_arr[e_arr.length - 1].from.get(0);
            yield this.call_void(
                Util.JS.callable(
                    "conversation_email_list.add"
                ).string(subject),
                this.load_cancellable
            );

            int? last_expanded_email_id = null;
            foreach (Geary.Email email in emails) {
                ConversationEmail conversation_email = new ConversationEmail(
                    this,
                    conversation,
                    email,
                    this.email_store,
                    this.contacts,
                    this.config,
                    is_sent(email),
                    is_draft(email)
                );
                this.conversation_emails.append_val(conversation_email);
                yield add_conversation_email(conversation_email);
                if (is_interesting(email)) {
                    last_expanded_email_id = (int) email.id.hash();
                    this.expand(
                        last_expanded_email_id,
                        this.load_cancellable
                    );
                }
            }
            if (last_expanded_email_id == null && emails.size > 0) {
                this.expand(
                    (int) emails.to_array()[0].id.hash(),
                    this.load_cancellable
                );
            } else if (last_expanded_email_id != null) {
                this.scrollTo(
                    last_expanded_email_id,
                    this.load_cancellable
                );
            }
        }
        this.call_void.begin(
            Util.JS.callable(
                "conversation_email_list.setLoaded"
            ), load_cancellable
        );
    }

    public void expand(int email_id, GLib.Cancellable load_cancellable) {
        this.call_void.begin(
            Util.JS.callable(
                "conversation_email.expand"
            ).int(email_id)
            , load_cancellable
        );
    }

    public void collapse(int email_id, GLib.Cancellable load_cancellable) {
        this.call_void.begin(
            Util.JS.callable(
                "conversation_email.collapse"
            ).int(email_id)
            , load_cancellable
        );
    }

    public void scrollTo(int email_id, GLib.Cancellable load_cancellable) {
        this.call_void.begin(
            Util.JS.callable(
                "conversation_email_list.scrollTo"
            ).int(email_id)
            , load_cancellable
        );
    }

    protected override void handle_avatar_request(WebKit.URISchemeRequest request) {
        int64 email_id = int64.parse(request.get_path());

        foreach (ConversationEmail conversation_email in this.conversation_emails) {
            if (conversation_email.email.id.hash() == email_id) {
                handle_avatar_request_for_email.begin(request, conversation_email.email);
                break;
            }
        }
    }

    protected override void handle_iframe_request(WebKit.URISchemeRequest request) {
        int64 email_id = int64.parse(request.get_path());

        foreach (ConversationEmail conversation_email in this.conversation_emails) {
            if (conversation_email.email.id.hash() == email_id) {
                handle_iframe_request_for_email.begin(request, conversation_email);
                break;
            }
        }
    }

    private async void add_conversation_email(ConversationEmail conversation_email,
                                              int position=-1) {

        try {
            yield conversation_email.add(this.load_cancellable);
            yield this.call_void(
                Util.JS.callable(
                    "conversation_email_list.insert_email"
                ).int((int) conversation_email.email.id.hash())
                , this.load_cancellable
            );
        } catch (GLib.Error err) {
            error("Failed to add email: %s", err.message);
        }
    }

    /** Determines if an email should be considered to be a draft. */
    private inline bool is_draft(Geary.Email email) {
        // XXX should be able to edit draft emails from any
        // conversation. This test should be more like "is in drafts
        // folder
        Geary.Folder.SpecialUse use = this.conversation.base_folder.used_as;
        bool is_in_folder = this.conversation.is_in_base_folder(email.id);

        return (
            is_in_folder && use == DRAFTS // ||
            //email.flags.is_draft()
        );
        return false;
    }

    /** Determines if an email should be expanded by default. */
    private inline bool is_interesting(Geary.Email email) {
        return (
            email.is_unread().is_certain() ||
            email.is_flagged().is_certain() ||
            is_draft(email)
        );
    }

    /** Determines if an email should be expanded by default. */
    private inline bool is_sent(Geary.Email email) {
        Geary.Account account = this.conversation.base_folder.account;
        if (email.from != null) {
            foreach (Geary.RFC822.MailboxAddress from in email.from) {
                if (account.information.has_sender_mailbox(from)) {
                    return true;
                }
            }
        }
        return false;
    }

    private async void handle_avatar_request_for_email(WebKit.URISchemeRequest request,
                                                       Geary.Email email) {
        try {
            Application.Contact? primary_contact = null;
            Geary.RFC822.MailboxAddress? primary_originator =
                Util.Email.get_primary_originator(email);
            if (primary_originator != null) {
                primary_contact = yield this.contacts.load(
                    primary_originator, this.load_cancellable
                );
            }
            if (primary_contact != null) {
                if (primary_contact.avatar != null) {
                    GLib.InputStream stream = yield primary_contact.avatar.load_async(
                        Application.Client.AVATAR_SIZE_PIXELS,
                        this.load_cancellable
                    );
                    request.finish(stream, -1, "image/png");
                } else {
                    GLib.MemoryInputStream stream = new GLib.MemoryInputStream();
                    Util.Avatar.generate_user_picture(primary_contact.display_name,
                                                      stream);
                    request.finish(stream, -1, "image/png");
                }
            }

        } catch (GLib.Error err) {
            request.finish_error(err);
        }
    }

     private async void handle_iframe_request_for_email(WebKit.URISchemeRequest request,
                                                        ConversationEmail conversation_email) {
        try {
            string body = yield conversation_email.get_body(this.load_cancellable);
            if (body != null) {
                GLib.InputStream stream = new GLib.MemoryInputStream.from_data(
                    body.data, GLib.g_free
                );
                request.finish(stream, -1, "text/html");
            }

        } catch (GLib.Error err) {
            request.finish_error(err);
        }
    }

    private void on_images_policy_clicked(uint x, uint y, uint width, uint height) {
        var images_policy_menu = new ConversationImagesPolicyMenu(this.primary_address);
        Gdk.Rectangle location = Gdk.Rectangle();

        location.x = (int) (x * this.zoom_level);
        location.y = (int) (y * this.zoom_level);
        location.width = (int) (width * this.zoom_level);
        location.height = (int) (height * this.zoom_level);

        images_policy_menu.set_relative_to(this);
        images_policy_menu.set_pointing_to(location);
        images_policy_menu.popup();
    }
}

