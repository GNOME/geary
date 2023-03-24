/*
 * Copyright 2023 Cedric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying image policy menu
 */
public class ConversationImagesPolicyMenu : Gtk.Popover {

    private const string ACTION_SHOW_IMAGES_CONVERSATION = "conv.show-images-conversation";
    private const string ACTION_SHOW_IMAGES_SENDER = "conv.show-images-sender";
    private const string ACTION_SHOW_IMAGES_DOMAIN = "conv.show-images-domain";

    /**
     * Constructs a new menu instance.
     */
    public ConversationImagesPolicyMenu(Geary.RFC822.MailboxAddress? address) {
        GLib.Menu menu_section = new GLib.Menu();
        GLib.MenuItem menu_item;

        menu_item = new GLib.MenuItem(
            _("For this conversation"), ACTION_SHOW_IMAGES_CONVERSATION
        );
        menu_section.append_item(menu_item);

        if (address == null) {
            menu_item = new GLib.MenuItem(
                _("For this sender"), ACTION_SHOW_IMAGES_SENDER
            );
            menu_section.append_item(menu_item);
            menu_item = new GLib.MenuItem(
                _("For this domain"), ACTION_SHOW_IMAGES_DOMAIN
            );
        } else {
            string target = address.address;

            menu_item = new GLib.MenuItem(
                _(@"For $target"), ACTION_SHOW_IMAGES_SENDER
            );
            menu_section.append_item(menu_item);

            target = address.domain;
            menu_item = new GLib.MenuItem(
                _(@"For @$target"), ACTION_SHOW_IMAGES_DOMAIN
            );
            menu_section.append_item(menu_item);
        }

        GLib.Menu menu_model = new GLib.Menu();
        menu_model.append_section(_("Show images"), menu_section);
        this.bind_model(
            menu_model,
            null
        );
    }
}


