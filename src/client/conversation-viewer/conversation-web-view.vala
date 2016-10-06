/* 
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : ClientWebView {

    private const string USER_CSS = "user-message.css";


    public bool is_height_valid { get; private set; default = false; }


    public ConversationWebView() {
        File user_css = GearyApplication.instance.get_user_config_directory().get_child(USER_CSS);
        // Print out a debug line here if the user CSS file exists, so
        // we get warning about it when debugging visual issues.
        user_css.query_info_async.begin(
            FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NONE,
            Priority.DEFAULT_IDLE,
            null,
            (obj, res) => {
                try {
                    user_css.query_info_async.end(res);
                    debug("User CSS file exists: %s", USER_CSS);
                } catch (Error e) {
                    // No problem, file does not exist
                }
            });

        WebKit.UserStyleSheet user_style = new WebKit.UserStyleSheet(
            user_css.get_uri(),
            WebKit.UserContentInjectedFrames.ALL_FRAMES,
            WebKit.UserStyleLevel.USER,
            null,
            null
        );

        WebKit.UserContentManager content = new WebKit.UserContentManager();
        content.add_style_sheet(user_style);

        base(content);

        // Set defaults.
        set_border_width(0);
    }

    public bool clean_and_load(string html) {
        // XXX clean me
        load_html(html, null);
        return false; // XXX Work this thes hit out
    }

    public bool has_selection() {
        bool has_selection = false; // XXX set me
        return has_selection;
    }

    /**
     * Returns the current selection, for prefill as find text.
     */
    public string get_selection_for_find() {
        return ""; // XXX
    }

    /**
     * Returns the current selection, for quoting in a message.
     */
    public string get_selection_for_quoting() {
        return ""; // XXX
    }

    /**
     * XXX
     */
    public void unset_controllable_quotes() {
        // XXX
    }

    /**
     * XXX
     */
    public void show_images() {
        // XXX
    }

    // Overridden since WebKitGTK+ 2.4.10 at least doesn't want to
    // report a useful height. In combination with the rules from
    // ui/conversation-web-view.css we can get an accurate idea of
    // the actual height of the content from the BODY element, but
    // only once loaded.
    public override void get_preferred_height(out int minimum_height,
                                              out int natural_height) {
        // Silence the "How does the code know the size to allocate?"
        // warning in GTK 3.20-ish.
        base.get_preferred_height(out minimum_height, out natural_height);

        long offset_height = 0; // XXX set me

        if (offset_height > 0) {
            // Avoid multiple notify signals?
            if (!this.is_height_valid) {
                this.is_height_valid = true;
            }
        }

        minimum_height = natural_height = (int) offset_height;
    }

    // Overridden since we always what the view to be sized according
    // to the available space in the parent, not by the width of the
    // web view.
    public override void get_preferred_width(out int minimum_height,
                                             out int natural_height) {
        // Silence the "How does the code know the size to allocate?"
        // warning in GTK 3.20-ish.
        base.get_preferred_width(out minimum_height, out natural_height);
        minimum_height = natural_height = 0;
    }

}
