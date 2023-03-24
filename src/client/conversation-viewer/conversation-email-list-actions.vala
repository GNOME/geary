/*
 * Copyright 2023 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Handle conversation viewer actions
 */
public class ConversationEmailListActions : Geary.BaseInterface {

    private const string ACTION_SHOW_IMAGES_CONVERSATION = "show-images-conversation";
    private const string ACTION_SHOW_IMAGES_SENDER = "show-images-sender";
    private const string ACTION_SHOW_IMAGES_DOMAIN = "show-images-domain";

    private ConversationWebView web_view;

    private Application.Configuration config;

    private Application.Contact? primary_contact { get; set; default=null; }

    private SimpleActionGroup conversation_actions = new SimpleActionGroup();

    /**
     * Constructs a new action handler
     */
    public ConversationEmailListActions(ConversationWebView web_view,
                                        Application.Configuration config) {
        base_ref();
        this.web_view = web_view;
        this.config = config;
        this.primary_contact = primary_contact;

        add_action(ACTION_SHOW_IMAGES_CONVERSATION, true)
            .activate.connect(on_show_images);
        add_action(ACTION_SHOW_IMAGES_SENDER, true)
            .activate.connect(on_show_images_sender);
        add_action(ACTION_SHOW_IMAGES_DOMAIN, true)
            .activate.connect(on_show_images_domain);
        web_view.insert_action_group("conv", this.conversation_actions);
    }

    ~ConversationEmailListActions() {
        base_unref();
    }

/*
    public void set_primary_contact(Application.Contact? contact) {
        this.primary_contact = contact;
        update_actions();
    }*/

    private SimpleAction add_action(string name, bool enabled, VariantType? type = null) {
        SimpleAction action = new SimpleAction(name, type);
        action.set_enabled(enabled);
        this.conversation_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action =
            this.conversation_actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void update_actions() {
    }

    private void show_images() {
        /*if (this.web_view != null) {
            this.web_view.load_remote_resources.begin(null);
        }*/
    }


    private void on_show_images(Variant? param) {
        show_images();
    }

    private void on_show_images_sender(Variant? param) {
        show_images();
        if (this.primary_contact != null) {
            this.primary_contact.set_remote_resource_loading.begin(
                true, null
            );
        }
    }

    private void on_show_images_domain(Variant? param) {
        show_images();
        if (this.primary_contact != null) {
            var email_addresses = this.primary_contact.email_addresses;
            foreach (Geary.RFC822.MailboxAddress email in email_addresses) {
                this.config.add_images_trusted_domain(email.domain);
                break;
            }
        }
    }
}


