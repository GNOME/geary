/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Regex to detect URLs.
// Originally from here: http://daringfireball.net/2010/07/improved_regex_for_matching_urls
public const string URL_REGEX = "(?i)\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))";

// Regex to determine if a URL has a known protocol.
public const string PROTOCOL_REGEX = "^(aim|apt|bitcoin|cvs|ed2k|ftp|file|finger|git|gtalk|http|https|irc|ircs|irc6|lastfm|ldap|ldaps|magnet|news|nntp|rsync|sftp|skype|smb|sms|svn|telnet|tftp|ssh|webcal|xmpp):";

// Private use unicode characters are used for quote tokens
public const string QUOTE_START = "";
public const string QUOTE_END = "";

// TODO Move these other functions and variables into this namespace.
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
        return node.clone_node(deep) as WebKit.DOM.HTMLElement;
    }

    public WebKit.DOM.HTMLElement? clone_select(WebKit.DOM.Node node, string selector,
        bool deep = true) {
        return clone_node(select(node, selector), deep);
    }

    public void toggle_class(WebKit.DOM.DOMTokenList class_list, string clas, bool add) throws Error {
        if (add) {
            class_list.add(clas);
        } else {
            class_list.remove(clas);
        }
    }
    
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
}

public void bind_event(WebKit.WebView view, string selector, string event, Callback callback,
    Object? extra = null) {
    try {
        WebKit.DOM.NodeList node_list = view.get_dom_document().query_selector_all(selector);
        for (int i = 0; i < node_list.length; ++i) {
            WebKit.DOM.EventTarget node = node_list.item(i) as WebKit.DOM.EventTarget;
            node.remove_event_listener(event, callback, false);
            node.add_event_listener(event, callback, false, extra);
        }
    } catch (Error error) {
        warning("Error setting up click handlers: %s", error.message);
    }
}

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
        debug("URL parsing error: %s\n", e.message);
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
            Regex r = new Regex(URL_REGEX, RegexCompileFlags.CASELESS);
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
        debug("URL parsing error: %s\n", e.message);
    }
    return false; // False to continue processing.
}

// Converts plain text emails to something safe and usable in HTML.
public string linkify_and_escape_plain_text(string input) throws Error {
    // Convert < and > into non-printable characters, and change & to &amp;.
    string output = input.replace("<", " \01 ").replace(">", " \02 ").replace("&", "&amp;");
    
    // Converts text links into HTML hyperlinks.
    Regex r = new Regex(URL_REGEX, RegexCompileFlags.CASELESS);
    
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

public WebKit.DOM.HTMLElement? closest_ancestor(WebKit.DOM.Element element, string selector) {
    try {
        WebKit.DOM.Element? parent = element.get_parent_element();
        while (parent != null && !parent.webkit_matches_selector(selector)) {
            parent = parent.get_parent_element();
        }
        return parent as WebKit.DOM.HTMLElement;
    } catch (Error error) {
        warning("Failed to find ancestor: %s", error.message);
        return null;
    }
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

// This will modify/reset the DOM
public string html_to_flowed_text(WebKit.DOM.HTMLElement el) {
    string saved_doc = el.get_inner_html();
    WebKit.DOM.NodeList blockquotes;
    try {
        blockquotes = el.query_selector_all("blockquote");
    } catch (Error error) {
        debug("Error selecting blockquotes: %s", error.message);
        return "";
    }
    
    int nbq = (int) blockquotes.length;
    string[] bqtexts = new string[nbq];
    
    // Get text of blockquotes and pull them out of DOM.  They are replaced with tokens deliminated
    // with the characters QUOTE_START and QUOTE_END (from a unicode private use block).  We need to
    // get the text while they're  still in the DOM to get newlines at appropriate places.  We go
    // through the list of blockquotes from the end so that we get the innermost ones first.
    for (int i = nbq - 1; i >= 0; i--) {
        WebKit.DOM.HTMLElement bq = (WebKit.DOM.HTMLElement) blockquotes.item(i);
        bqtexts[i] = bq.get_inner_text();
        if (bqtexts[i].substring(-1, 1) == "\n")
            bqtexts[i] = bqtexts[i].slice(0, -1);
        else
            debug("Did not find expected newline at end of quote.");
        
        try {
            bq.set_inner_text(@"$QUOTE_START$i$QUOTE_END");
        } catch (Error error) {
            debug("Error manipulating DOM: %s", error.message);
        }
    }
    
    // Reassemble plain text out of parts, replace non-breaking space with regular space
    string doctext = resolve_nesting(el.get_inner_text(), bqtexts).replace("\xc2\xa0", " ");
    
    // Reassemble DOM
    try {
        el.set_inner_html(saved_doc);
    } catch (Error error) {
        debug("Error resetting DOM: %s", error.message);
    }
    
    // Wrap, space stuff, quote
    string[] lines = doctext.split("\n");
    GLib.StringBuilder flowed = new GLib.StringBuilder.sized(doctext.length);
    foreach (string line in lines) {
        line = line.chomp();
        int quote_level = 0;
        while (line[quote_level] == Geary.RFC822.Utils.QUOTE_MARKER)
            quote_level += 1;
        line = line[quote_level:line.length];
        string prefix = quote_level > 0 ? string.nfill(quote_level, '>') + " " : "";
        int max_len = 72 - prefix.length;
        
        do {
            if (quote_level == 0 && (line.has_prefix(">") || line.has_prefix("From")))
                line = " " + line;
            
            int cut_ind = line.length;
            if (cut_ind > max_len) {
                string beg = line[0:max_len];
                cut_ind = beg.last_index_of(" ") + 1;
                if (cut_ind == 0) {
                    cut_ind = line.index_of(" ") + 1;
                    if (cut_ind == 0)
                        cut_ind = line.length;
                    if (cut_ind > 998 - prefix.length)
                        cut_ind = 998 - prefix.length;
                }
            }
            flowed.append(prefix + line[0:cut_ind] + "\n");
            line = line[cut_ind:line.length];
        } while (line.length > 0);
    }
    
    return flowed.str;
}

public string quote_lines(string text) {
    string[] lines = text.split("\n");
    for (int i=0; i<lines.length; i++)
        lines[i] = @"$(Geary.RFC822.Utils.QUOTE_MARKER)" + lines[i];
    return string.joinv("\n", lines);
}

public string resolve_nesting(string text, string[] values) {
    try {
        GLib.Regex tokenregex = new GLib.Regex(@"(.?)$QUOTE_START([0-9]*)$QUOTE_END(?=(.?))");
        return tokenregex.replace_eval(text, -1, 0, 0, (info, res) => {
            int key = int.parse(info.fetch(2));
            string prev_char = info.fetch(1), next_char = info.fetch(3), insert_next = "";
            // Make sure there's a newline before and after the quote.
            if (prev_char != "" && prev_char != "\n")
                prev_char = prev_char + "\n";
            if (next_char != "" && next_char != "\n")
                insert_next = "\n";
            if (key >= 0 && key < values.length) {
                res.append(prev_char + quote_lines(resolve_nesting(values[key], values)) + insert_next);
            } else {
                debug("Regex error in denesting blockquotes: Invalid key");
                res.append("");
            }
            return false;
        });
    } catch (Error error) {
        debug("Regex error in denesting blockquotes: %s", error.message);
        return "";
    }
}

// Returns a URI suitable for an IMG SRC attribute (or elsewhere, potentially) that is the
// memory buffer unpacked into a Base-64 encoded data: URI
public string assemble_data_uri(string mimetype, Geary.Memory.Buffer buffer) {
    // attempt to use UnownedBytesBuffer to avoid memcpying a potentially huge buffer only to
    // free it when the encoding operation is completed
    string base64;
    Geary.Memory.UnownedBytesBuffer? unowned_bytes = buffer as Geary.Memory.UnownedBytesBuffer;
    if (unowned_bytes != null)
        base64 = Base64.encode(unowned_bytes.to_unowned_uint8_array());
    else
        base64 = Base64.encode(buffer.get_uint8_array());
    
    return "data:%s;base64,%s".printf(mimetype, base64);
}

// Turns the data: URI created by assemble_data_uri() back into its components.  The returned
// buffer is decoded.
//
// TODO: Return mimetype
public bool dissasemble_data_uri(string uri, out Geary.Memory.Buffer? buffer) {
    buffer = null;
    
    if (!uri.has_prefix("data:"))
        return false;
    
    // count from semicolon past encoding type specifier
    int start_index = uri.index_of(";");
    if (start_index <= 0)
        return false;
    
    // watch for string termination to avoid overflow
    int base64_len = "base64,".length;
    for (int ctr = 0; ctr < base64_len; ctr++) {
        if (uri[start_index++] == Geary.String.EOS)
            return false;
    }
    
    // avoid a memory copy of the substring by manually calculating the start address
    uint8[] bytes = Base64.decode((string) (((char *) uri) + start_index));
    
    // transfer ownership of the byte array directly to the Buffer; this prevents an
    // unnecessary copy ... save length before transferring ownership (which frees the array)
    int bytes_length = bytes.length;
    buffer = new Geary.Memory.ByteBuffer.take((owned) bytes, bytes_length);
    
    return true;
}

