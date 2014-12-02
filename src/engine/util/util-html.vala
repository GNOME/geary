/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.HTML {

private int init_count = 0;
private Gee.HashSet<string>? breaking_elements = null;

/**
 * Must be called before ''any'' call to the HTML namespace.
 *
 * This will be initialized by the Engine when it's opened; or call this
 * directly to use these functions earlier.
 */
public void init() {
    if (init_count++ != 0)
        return;
    
    init_breaking_elements();
}

private void init_breaking_elements() {
    // Organized from <https://en.wikipedia.org/wiki/HTML_element>.  This is a
    // list of block elements and some others that get special treatment.
    // NOTE: this SHOULD be a const list, but due to
    // <https://bugzilla.gnome.org/show_bug.cgi?id=646970>, it can't be.
    string[] elements = {
        "address",
        "blockquote",
        "br", // [1]
        "caption", // [2]
        "center",
        "dd",
        "del", // [3]
        "dir",
        "div",
        "dl",
        "dt",
        "embed",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "hr",
        "img", // [1]
        "ins", // [3]
        "li",
        "map", // [1]
        "menu",
        "noscript", // [2]
        "object", // [1]
        "ol",
        "p",
        "pre",
        "script", // [2]
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "tr",
        "ul",
        
        // [1]: Not block elements, but still break up the text
        // [2]: Some of these are oddities, but I figure they should break flow
        // [3]: Can be used as either block or inline; we go for broke
    };
    
    breaking_elements = new Gee.HashSet<string>(Ascii.stri_hash, Ascii.stri_equal);
    foreach (string element in elements)
        breaking_elements.add(element);
}

public inline string escape_markup(string? plain) {
    return (!String.is_empty(plain) && plain.validate()) ? Markup.escape_text(plain) : "";
}

public string preserve_whitespace(string? text) {
    if (String.is_empty(text))
        return "";
    
    string output = text.replace(" ", "&nbsp;");
    output = output.replace("\r\n", "<br />");
    output = output.replace("\n", "<br />");
    output = output.replace("\r", "<br />");

    return output;
}

public string smart_escape(string? text, bool preserve_whitespace_in_html) {
    if (text == null)
        return text;
    
    string res = text;
    if (!Regex.match_simple("<([A-Z]*)[^>]*>.*</(\\1)>|<[^>]*/>", res,
        RegexCompileFlags.CASELESS)) {
        res = escape_markup(res);
        preserve_whitespace_in_html = true;
    }
    if (preserve_whitespace_in_html)
        res = @"<div style='white-space: pre;'>$res</div>";
    return res;
}

// Removes any text between < and >.  Additionally, if input terminates in the middle of a tag, 
// the tag will be removed.
// If the HTML is invalid, the original string will be returned.
public string remove_html_tags(string input) {
    try {
        string output = input;
        
        // Count the number of < and > characters.
        unichar c;
        uint64 less_than = 0;
        uint64 greater_than = 0;
        for (int i = 0; output.get_next_char (ref i, out c);) {
            if (c == '<')
                less_than++;
            else if (c == '>')
                greater_than++;
        }
        
        if (less_than == greater_than + 1) {
            output += ">"; // Append an extra > so our regex works.
            greater_than++;
        }
        
        if (less_than != greater_than)
            return input; // Invalid HTML.
        
        // Removes script tags and everything between them.
        // Based on regex here: http://stackoverflow.com/questions/116403/im-looking-for-a-regular-expression-to-remove-a-given-xhtml-tag-from-a-string
        Regex script = new Regex("<script[^>]*?>[\\s\\S]*?<\\/script>", RegexCompileFlags.CASELESS);
        output = script.replace(output, -1, 0, "");
        
        // Removes style tags and everything between them.
        // Based on regex above.
        Regex style = new Regex("<style[^>]*?>[\\s\\S]*?<\\/style>", RegexCompileFlags.CASELESS);
        output = style.replace(output, -1, 0, "");
        
        // Removes remaining tags.
        Regex tags = new Regex("<[^>]*>", RegexCompileFlags.CASELESS);
        return tags.replace(output, -1, 0, "");
    } catch (Error e) {
        debug("Error stripping HTML tags: %s", e.message);
    }
    
    return input;
}

/**
 * Does a very approximate conversion from HTML to text.
 *
 * This does more than stripping tags -- it inserts line breaks where appropriate, decodes
 * entities, etc.  The layout of the text is largely lost.  This is primarily
 * useful for pulling out tokens for searching, not for presenting to the user.
 */
public string html_to_text(string html, string encoding = "UTF-8") {
    Html.Doc *doc = Html.Doc.read_doc(html, "", encoding, Html.ParserOption.RECOVER |
        Html.ParserOption.NOERROR | Html.ParserOption.NOWARNING | Html.ParserOption.NOBLANKS |
        Html.ParserOption.NONET | Html.ParserOption.COMPACT);
    
    StringBuilder text = new StringBuilder();
    if (doc != null) {
        recurse_html_nodes_for_text(doc->get_root_element(), text);
        delete doc;
    }
    
    return text.str;
}

private void recurse_html_nodes_for_text(Xml.Node? node, StringBuilder text) {
    // TODO: add alt text for things that have it?
    
    for (unowned Xml.Node? n = node; n != null; n = n.next) {
        if (n.type == Xml.ElementType.TEXT_NODE)
            text.append(n.content);
        else if (n.type == Xml.ElementType.ELEMENT_NODE && element_needs_break(n.name))
            text.append("\n");
        
        recurse_html_nodes_for_text(n.children, text);
    }
}

// Determines if the named element should break the flow of text.
private bool element_needs_break(string element) {
    return breaking_elements.contains(element);
}

}
