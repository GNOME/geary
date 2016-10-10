/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Initialises GearyWebExtension for WebKit web processes.
 */
public void webkit_web_extension_initialize_with_user_data(WebKit.WebExtension extension,
                                                           Variant data) {
    bool logging_enabled = data.get_boolean();

    Geary.Logging.init();
    if (logging_enabled)
        Geary.Logging.log_to(stdout);

    debug("Initialising...");

    // Ref it so it doesn't get free'ed right away
    GearyWebExtension instance = new GearyWebExtension(extension);
    instance.ref();
}

/**
 * A WebExtension that manages Geary-specific behaviours in web processes.
 */
public class GearyWebExtension : Object {


    private WebKit.WebExtension extension;

    private string allow_prefix;


    public GearyWebExtension(WebKit.WebExtension extension) {
        this.extension = extension;
        this.allow_prefix = random_string(10) + ":";

        extension.page_created.connect((extension, web_page) => {
                web_page.send_request.connect(on_send_request);
            });
    }

    private bool on_send_request(WebKit.WebPage page,
                                 WebKit.URIRequest request,
                                 WebKit.URIResponse? response) {
        const string CID_PREFIX = "cid:";
        const string DATA_PREFIX = "data:";

        bool should_load = false;
        string req_uri = request.get_uri();
        if (req_uri.has_prefix(CID_PREFIX) |
            req_uri.has_prefix(DATA_PREFIX)) {
            should_load = true;
        } else if (req_uri.has_prefix(this.allow_prefix)) {
            should_load = true;
            request.set_uri(req_uri.substring(this.allow_prefix.length));
        }

        return should_load ? Gdk.EVENT_PROPAGATE : Gdk.EVENT_STOP; // LOL
    }

}

private string random_string(int length) {
    // No upper case letters, since request gets lower-cased.
    string chars = "abcdefghijklmnopqrstuvwxyz";
    char[] random = new char[length+1]; //leave room for terminating null
    for (int i = 0; i < length; i++)
        random[i] = chars[Random.int_range(0, chars.length)];
    random[length] = '\0'; //make sure the string is null-terminated
    return (string) random;
}
