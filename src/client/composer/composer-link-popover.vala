/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/**
 * A popover for editing a link in the composer.
 *
 * The exact appearance of the popover will depend on the {@link
 * Type} passed to the constructor:
 *
 *  * For {@link Type.NEW_LINK}, the user will be presented with an
 *    insert button and an open button.
 *  * For {@link Type.EXISTING_LINK}, the user will be presented with
 *    an update, delete and open buttons.
 */
[GtkTemplate (ui = "/org/gnome/Geary/composer-link-popover.ui")]
public class Composer.LinkPopover : Gtk.Popover {

    private const string[] HTTP_SCHEMES = { "http", "https" };
    private const string[] OTHER_SCHEMES = {
        "aim", "apt", "bitcoin", "cvs", "ed2k", "ftp", "file", "finger",
        "git", "gtalk", "irc", "ircs", "irc6", "lastfm", "ldap", "ldaps",
        "magnet", "news", "nntp", "rsync", "sftp", "skype", "smb", "sms",
        "svn", "telnet", "tftp", "ssh", "webcal", "xmpp"
    };

    /** Determines which version of the UI is presented to the user. */
    public enum Type {
        /** A new link is being created. */
        NEW_LINK,

        /** An existing link is being edited. */
        EXISTING_LINK,
    }

    /** The URL displayed in the popover */
    public string link_uri { get { return this.url.get_text(); } }

    [GtkChild] private unowned Gtk.Entry url;

    [GtkChild] private unowned Gtk.Button insert;

    [GtkChild] private unowned Gtk.Button update;

    [GtkChild] private new unowned Gtk.Button remove;

    private Geary.TimeoutManager validation_timeout;


    /** Emitted when the link URL has changed. */
    public signal void link_changed(GLib.Uri? uri, bool is_valid);

    /** Emitted when the link URL was activated. */
    public signal void link_activate();

    /** Emitted when the delete button was activated. */
    public signal void link_delete();


    public LinkPopover(Type type) {
        set_default_widget(this.url);
        set_focus_child(this.url);
        switch (type) {
        case Type.NEW_LINK:
            this.update.hide();
            this.remove.hide();
            break;
        case Type.EXISTING_LINK:
            this.insert.hide();
            break;
        }
        this.validation_timeout = new Geary.TimeoutManager.milliseconds(
            150, () => { validate(); }
        );
    }

    public override void show() {
        base.show();
        this.url.grab_focus();
    }

    public override void destroy() {
        this.validation_timeout.reset();
        base.destroy();
    }

    public void set_link_url(string url) {
        this.url.set_text(url);
        this.validation_timeout.reset(); // Don't update on manual set
    }

    private void validate() {
        string? text = this.url.get_text().strip();
        bool is_empty = Geary.String.is_empty(text);
        bool is_valid = false;
        bool is_nominal = false;
        bool is_mailto = false;
        GLib.Uri? url = null;
        if (!is_empty) {
            try {
                url = GLib.Uri.parse(text, PARSE_RELAXED);
            } catch (GLib.UriError err) {
                debug("Invalid link URI: %s", err.message);
            }
            if (url != null) {
                is_valid = true;

                string? scheme = url.get_scheme();
                string? path = url.get_path();
                if (scheme in HTTP_SCHEMES) {
                    is_nominal = Geary.Inet.is_valid_display_host(url.get_host());
                } else if (scheme == "mailto") {
                    is_mailto = true;
                    is_nominal = (
                        !Geary.String.is_empty(path) &&
                        Geary.RFC822.MailboxAddress.is_valid_address(path)
                    );
                } else if (scheme in OTHER_SCHEMES) {
                    is_nominal = !Geary.String.is_empty(path);
                }
            } else if (text == "http:/" || text == "https:/") {
                // Don't let the URL entry switch to invalid and back
                // between "http:" and "http://"
                is_valid = true;
            }
        }

        Gtk.StyleContext style = this.url.get_style_context();
        Gtk.EntryIconPosition pos = Gtk.EntryIconPosition.SECONDARY;
        if (!is_valid) {
            style.add_class(Gtk.STYLE_CLASS_ERROR);
            style.remove_class(Gtk.STYLE_CLASS_WARNING);
            this.url.set_icon_from_icon_name(pos, "dialog-error-symbolic");
            this.url.set_tooltip_text(
                _("Link URL is not correctly formatted, e.g. http://example.com")
            );
        } else if (!is_nominal) {
            style.remove_class(Gtk.STYLE_CLASS_ERROR);
            style.add_class(Gtk.STYLE_CLASS_WARNING);
            this.url.set_icon_from_icon_name(pos, "dialog-warning-symbolic");
            this.url.set_tooltip_text(
                !is_mailto ? _("Invalid link URL") : _("Invalid email address")
            );
        } else {
            style.remove_class(Gtk.STYLE_CLASS_ERROR);
            style.remove_class(Gtk.STYLE_CLASS_WARNING);
            this.url.set_icon_from_icon_name(pos, null);
            this.url.set_tooltip_text("");
        }

        link_changed(url, is_valid && is_nominal);
    }

    [GtkCallback]
    private void on_url_changed() {
        this.validation_timeout.start();
    }

    [GtkCallback]
    private void on_activate_popover() {
        link_activate();
        popdown();
    }

    [GtkCallback]
    private void on_remove_clicked() {
        link_delete();
        popdown();
    }
}
