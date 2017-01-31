/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Regex to determine if a URL has a known protocol.
public const string PROTOCOL_REGEX = "^(aim|apt|bitcoin|cvs|ed2k|ftp|file|finger|git|gtalk|http|https|irc|ircs|irc6|lastfm|ldap|ldaps|magnet|news|nntp|rsync|sftp|skype|smb|sms|svn|telnet|tftp|ssh|webcal|xmpp):";

namespace Util.DOM {
    public WebKit.DOM.HTMLElement? select(WebKit.DOM.Node node, string selector) {
        try {
            if (node is WebKit.DOM.Document) {
                return (node as WebKit.DOM.Document).query_selector(selector) as WebKit.DOM.HTMLElement;
            } else {
                return (node as WebKit.DOM.Element).query_selector(selector) as WebKit.DOM.HTMLElement;
            }
        } catch (Error error) {
            debug("Error selecting element %s: %s", selector, error.message);
            return null;
        }
    }

    public WebKit.DOM.HTMLElement? clone_node(WebKit.DOM.Node node, bool deep = true) {
        WebKit.DOM.HTMLElement? clone = null;
        try {
            clone = node.clone_node(deep) as WebKit.DOM.HTMLElement;
        } catch (Error err) {
            debug("Error selecting cloning node: %s", err.message);
        }
        return clone;
    }

    public WebKit.DOM.HTMLElement? clone_select(WebKit.DOM.Node node, string selector,
        bool deep = true) {
        return clone_node(select(node, selector), deep);
    }

    //public void toggle_class(WebKit.DOM.DOMTokenList class_list, string clas, bool add) throws Error {
    //     if (add) {
    //         class_list.add(clas);
    //     } else {
    //         class_list.remove(clas);
    //     }
    //}

    // Returns the text contained in the DOM document, after ignoring tags of type "exclude"
    // and padding newlines where appropriate. Used to scan for attachment keywords.
    public string get_text_representation(WebKit.DOM.Document doc, string exclude) {
        WebKit.DOM.HTMLElement? copy = Util.DOM.clone_node(doc.get_body());
        if (copy == null) {
            return "";
        }

        // Keep deleting the next excluded element until there are none left
        while (true) {
            WebKit.DOM.HTMLElement? current = Util.DOM.select(copy, exclude);
            if (current == null) {
                break;
            }

            WebKit.DOM.Node parent = current.get_parent_node();
            try {
                parent.remove_child(current);
            } catch (Error error) {
                debug("Error removing blockquotes: %s", error.message);
                break;
            }
        }

        WebKit.DOM.NodeList node_list;
        try {
            node_list = copy.query_selector_all("br");
        } catch (Error error) {
            debug("Error finding <br>s: %s", error.message);
            return copy.get_inner_text();
        }

        // Replace <br> tags with newlines
        for (int i = 0; i < node_list.length; ++i) {
            WebKit.DOM.Node br = node_list.item(i);
            WebKit.DOM.Node parent = br.get_parent_node();
            try {
                parent.replace_child(doc.create_text_node("\n"), br);
            } catch (Error error) {
                debug("Error replacing <br>: %s", error.message);
            }
        }

        try {
            node_list = copy.query_selector_all("div");
        } catch (Error error) {
            debug("Error finding <div>s: %s", error.message);
            return copy.get_inner_text();
        }

        // Pad each <div> with newlines
        for (int i = 0; i < node_list.length; ++i) {
            WebKit.DOM.Node div = node_list.item(i);
            try {
                div.insert_before(doc.create_text_node("\n"), div.first_child);
                div.append_child(doc.create_text_node("\n"));
            } catch (Error error) {
                debug("Error padding <div> with newlines: %s", error.message);
            }
        }
        return copy.get_inner_text();
    }

    // public void bind_event(WebKit.WebView view, string selector, string event, Callback callback,
    //     Object? extra = null) {
    //     try {
    //         WebKit.DOM.NodeList node_list = view.get_dom_document().query_selector_all(selector);
    //         for (int i = 0; i < node_list.length; ++i) {
    //             WebKit.DOM.EventTarget node = node_list.item(i) as WebKit.DOM.EventTarget;
    //             node.remove_event_listener(event, callback, false);
    //             node.add_event_listener(event, callback, false, extra);
    //         }
    //     } catch (Error error) {
    //         warning("Error setting up click handlers: %s", error.message);
    //     }
    // }

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

    public bool node_is_child_of(WebKit.DOM.Node node, string ancestor_tag) {
        WebKit.DOM.Element? ancestor = node.get_parent_element();
        for (; ancestor != null; ancestor = ancestor.get_parent_element()) {
            if (ancestor.get_tag_name() == ancestor_tag) {
                return true;
            }
        }
        return false;
    }

    public bool is_descendant_of(WebKit.DOM.Element? element, string selector) {
        try {
            WebKit.DOM.NodeList matching = element.owner_document.query_selector_all(selector);
            for (int i = 0; i < matching.length; i++) {
                WebKit.DOM.Node parent = matching.item(i);
                WebKit.DOM.Node child = element;
                while (child != null) {
                    if (child.parent_node == parent) {
                        return true;
                    }
                    child = child.parent_node;
                }
            }
        } catch (Error error) {
            warning("Problem traversing DOM: %s", error.message);
        }
        return false;
    }

    public string decorate_quotes(string text) throws Error {
        int level = 0;
        string outtext = "";
        Regex quote_leader = new Regex("^(&gt;)* ?");  // Some &gt; followed by optional space

        foreach (string line in text.split("\n")) {
            MatchInfo match_info;
            if (quote_leader.match_all(line, 0, out match_info)) {
                int start, end, new_level;
                match_info.fetch_pos(0, out start, out end);
                new_level = end / 4;  // Cast to int removes 0.25 from space at end, if present
                while (new_level > level) {
                    outtext += "<blockquote>";
                    level += 1;
                }
                while (new_level < level) {
                    outtext += "</blockquote>";
                    level -= 1;
                }
                outtext += line.substring(end);
            } else {
                debug("This line didn't match the quote regex: %s", line);
                outtext += line;
            }
        }
        // Close any remaining blockquotes.
        while (level > 0) {
            outtext += "</blockquote>";
            level -= 1;
        }
        return outtext;
    }

}
