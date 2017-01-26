/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Regex to determine if a URL has a known protocol.
public const string PROTOCOL_REGEX = "^(aim|apt|bitcoin|cvs|ed2k|ftp|file|finger|git|gtalk|http|https|irc|ircs|irc6|lastfm|ldap|ldaps|magnet|news|nntp|rsync|sftp|skype|smb|sms|svn|telnet|tftp|ssh|webcal|xmpp):";

namespace Util.DOM {

    // Linkifies plain text links in an HTML document.
    public void linkify_document(WebKit.DOM.Document document) {
        linkify_recurse(document, document.get_body());
    }

    // Validates a URL.
    // Ensures the URL begins with a valid protocol specifier.  (If not, we don't
    // want to linkify it.)
    // Note that the output of this will place '\01' chars before and after a link,
    // which we use to split the string in linkify()
    private bool pre_split_urls(MatchInfo match_info, StringBuilder result) {
        try {
            string? url = match_info.fetch(0);
            Regex r = new Regex(PROTOCOL_REGEX, RegexCompileFlags.CASELESS);
            result.append(r.match(url) ? "\01%s\01".printf(url) : url);
        } catch (Error e) {
            debug("URL parsing error: %s", e.message);
        }
        return false; // False to continue processing.
    }

    // Linkifies "plain text" links in the HTML doc.  If you want to do this
    // for the entire document, use the get_dom_document().get_body() for the
    // node param and leave _in_link as false.
    private void linkify_recurse(WebKit.DOM.Document document, WebKit.DOM.Node node,
        bool _in_link = false) {

        bool in_link = _in_link;
        if (node is WebKit.DOM.HTMLAnchorElement)
            in_link = true;

        string input = node.get_node_value();
        if (!in_link && !Geary.String.is_empty(input)) {
            try {
                Regex r = new Regex(Geary.HTML.URL_REGEX, RegexCompileFlags.CASELESS);
                string output = r.replace_eval(input, -1, 0, 0, pre_split_urls);
                if (input != output) {
                    // We got one!  Now split the text and swap out the node.
                    Regex tester = new Regex(PROTOCOL_REGEX, RegexCompileFlags.CASELESS);
                    string[] pieces = output.split("\01");
                    Gee.ArrayList<WebKit.DOM.Node> new_nodes = new Gee.ArrayList<WebKit.DOM.Node>();

                    for(int i = 0; i < pieces.length; i++) {
                        //WebKit.DOM.Node new_node;
                        if (tester.match(pieces[i])) {
                            // Link part.
                            WebKit.DOM.HTMLAnchorElement anchor = document.create_element("a")
                                as WebKit.DOM.HTMLAnchorElement;
                            anchor.href = pieces[i];
                            anchor.set_inner_text(pieces[i]);
                            new_nodes.add(anchor);
                        } else {
                            // Text part.
                            WebKit.DOM.Node new_node = node.clone_node(false);
                            new_node.set_node_value(pieces[i]);
                            new_nodes.add(new_node);
                        }
                    }

                    // Add our new nodes.
                    WebKit.DOM.Node? sibling = node.get_next_sibling();
                    for (int i = 0; i < new_nodes.size; i++) {
                        WebKit.DOM.Node new_node = new_nodes.get(i);
                        if (sibling == null)
                            node.get_parent_node().append_child(new_node);
                        else
                            node.get_parent_node().insert_before(new_node, sibling);
                    }

                    // Remove the original node's text.
                    node.set_node_value("");
                }
            } catch (Error e) {
                debug("Error linkifying outgoing mail: %s", e.message);
            }
        }

        // Visit children.
        WebKit.DOM.NodeList list = node.get_child_nodes();
        for (int i = 0; i < list.length; i++) {
            linkify_recurse(document, list.item(i), in_link);
        }
    }

    // Validates a URL.  Intended to be used as a RegexEvalCallback.
    // Ensures the URL begins with a valid protocol specifier.  (If not, we don't
    // want to linkify it.)
    public bool is_valid_url(MatchInfo match_info, StringBuilder result) {
        try {
            string? url = match_info.fetch(0);
            Regex r = new Regex(PROTOCOL_REGEX, RegexCompileFlags.CASELESS);

            result.append(r.match(url) ? "<a href=\"%s\">%s</a>".printf(url, url) : url);
        } catch (Error e) {
            debug("URL parsing error: %s", e.message);
        }
        return false; // False to continue processing.
    }

    // Converts plain text emails to something safe and usable in HTML.
    public string linkify_and_escape_plain_text(string input) throws Error {
        // Convert < and > into non-printable characters, and change & to &amp;.
        string output = input.replace("<", " \01 ").replace(">", " \02 ").replace("&", "&amp;");

        // Converts text links into HTML hyperlinks.
        Regex r = new Regex(Geary.HTML.URL_REGEX, RegexCompileFlags.CASELESS);

        output = r.replace_eval(output, -1, 0, 0, is_valid_url);
        return output.replace(" \01 ", "&lt;").replace(" \02 ", "&gt;");
    }

}

