/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.HTML {

// Regex to detect URLs.
// Originally from here: http://daringfireball.net/2010/07/improved_regex_for_matching_urls
public const string URL_REGEX = "(?i)\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))";

private int init_count = 0;
private Gee.HashSet<string>? breaking_elements;
private Gee.HashSet<string>? spacing_elements;
private Gee.HashSet<string>? alt_text_elements;
private Gee.HashSet<string>? ignored_elements;

/**
 * Must be called before ''any'' call to the HTML namespace.
 *
 * This will be initialized by the Engine when it's opened; or call this
 * directly to use these functions earlier.
 */
public void init() {
    if (init_count++ != 0)
        return;

    init_element_sets();
}

private void init_element_sets() {
    // Organized from <https://en.wikipedia.org/wiki/HTML_element>,
    // <https://html.spec.whatwg.org/multipage> and some custom
    // inference.

    // Block elements and some others that cause new lines to be
    // inserted when converting to text. Not all block elements are
    // included since some (e.g. lists) will have nested breaking
    // children.
    breaking_elements = new Gee.HashSet<string>(Ascii.stri_hash, Ascii.stri_equal);
    breaking_elements.add_all_array({
        "address",
        "blockquote",
        "br", // [1]
        "caption", // [2]
        "center",
        "div",
        "dt",
        "embed",
        "form",
        "h1", "h2", "h3", "h4", "h5", "h6",
        "hr",
        "iframe", // [1]
        "li",
        "map", // [1]
        "menu",
        "noscript", // [2]
        "object", // [1]
        "p",
        "pre",
        "tr",

        // [1]: Not block elements, but still break up the text
        // [2]: Some of these are oddities, but I figure they should break flow
    });

    // Elements that cause spaces to be inserted afterwards when
    // converting to text.
    spacing_elements = new Gee.HashSet<string>(Ascii.stri_hash, Ascii.stri_equal);
    spacing_elements.add_all_array({
        "dt",
        "dd",
        "img",
        "td",
        "th",
    });

    // Elements that may have alt text
    alt_text_elements = new Gee.HashSet<string>(Ascii.stri_hash, Ascii.stri_equal);
    alt_text_elements.add_all_array({
        "img",
    });

    // Elements that should not be included when converting to text
    ignored_elements = new Gee.HashSet<string>(Ascii.stri_hash, Ascii.stri_equal);
    ignored_elements.add_all_array({
        "base",
        "link",
        "meta",
        "head",
        "script",
        "style",
        "template",
    });
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

/**
 * Does a very approximate conversion from HTML to text.
 *
 * This does more than stripping tags -- it inserts line breaks where
 * appropriate, decodes entities, etc. Note the full string is parsed
 * by libxml's HTML parser to create a DOM-like tree representation,
 * which is then walked, so this function can be somewhat
 * computationally expensive.
 */
public string html_to_text(string html,
                           bool include_blockquotes = true,
                           string encoding = Geary.RFC822.UTF8_CHARSET) {
    Html.Doc *doc = Html.Doc.read_doc(html, "", encoding, Html.ParserOption.RECOVER |
        Html.ParserOption.NOERROR | Html.ParserOption.NOWARNING | Html.ParserOption.NOBLANKS |
        Html.ParserOption.NONET | Html.ParserOption.COMPACT);

    StringBuilder text = new StringBuilder();
    if (doc != null) {
        recurse_html_nodes_for_text(doc->get_root_element(), include_blockquotes, text);
        delete doc;
    }

    return text.str;
}

private void recurse_html_nodes_for_text(Xml.Node? node,
                                         bool include_blockquotes,
                                         StringBuilder text) {
    for (unowned Xml.Node? n = node; n != null; n = n.next) {
        if (n.type == Xml.ElementType.TEXT_NODE) {
            text.append(n.content);
        } else if (n.type == Xml.ElementType.ELEMENT_NODE) {
            string name = n.name;
            if (include_blockquotes || name != "blockquote") {
                if (name in alt_text_elements) {
                    string? alt_text = node.get_prop("alt");
                    if (alt_text != null) {
                        text.append(alt_text);
                    }
                }

                if (!(name in ignored_elements)) {
                    recurse_html_nodes_for_text(n.children, include_blockquotes, text);
                }

                if (name in spacing_elements) {
                    text.append(" ");
                }

                if (name in breaking_elements) {
                    text.append("\n");
                }
            }
        }
    }
}

// Escape reserved HTML entities if the string does not have HTML
// tags.  If there are no tags, or if preserve_whitespace_in_html is
// true, wrap the string a div to preserve whitespace.
public string smart_escape(string? text, bool preserve_whitespace_in_html) {
    if (text == null)
        return text;

    string res = text;
    if (!Regex.match_simple("<[A-Z]*(?: [^>]*)?\\/?>", res,
                            RegexCompileFlags.CASELESS)) {
        res = Geary.HTML.escape_markup(res);
        preserve_whitespace_in_html = true;
    }
    if (preserve_whitespace_in_html)
        res = @"<div style='white-space: pre;'>$res</div>";
    return res;
}

}
