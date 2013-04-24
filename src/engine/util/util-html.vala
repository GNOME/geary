/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.HTML {

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
        
        // Removes remaining tags. Based on this regex:
        // http://osherove.com/blog/2003/5/13/strip-html-tags-from-a-string-using-regular-expressions.html
        Regex tags = new Regex("<(.|\n)*?>", RegexCompileFlags.CASELESS);
        return tags.replace(output, -1, 0, "");
    } catch (Error e) {
        debug("Error stripping HTML tags: %s", e.message);
    }
    
    return input;
}

}
