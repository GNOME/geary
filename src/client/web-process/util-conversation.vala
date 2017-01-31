/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Conversation {

    private const string SIGNATURE_CONTAINER_CLASS = "geary_signature";

    private const string QUOTE_CONTAINER_CLASS = "geary_quote_container";
    private const string QUOTE_CONTROLLABLE_CLASS = "controllable";
    private const string QUOTE_HIDE_CLASS = "hide";
    private const float QUOTE_SIZE_THRESHOLD = 2.0f;


    public double get_preferred_height(WebKit.WebPage page) {
        WebKit.DOM.Element html = page.get_dom_document().get_document_element();
        double offset_height = html.offset_height;
        double offset_width = html.offset_width;
        double px = offset_width * offset_height;

        const double MAX_LEN = 15.0 * 1000;
        const double MAX_PX = 10.0 * 1000 * 1000;

        // If the offset_width is very small, the offset_height will
        // likely be bogus, so just pretend we have no height for the
        // moment. WebKitGTK seems to report an offset width of 1 in
        // these cases.
        if (offset_width > 1) {
            if (offset_height > MAX_LEN || px > MAX_PX) {
                double new_height = double.min(MAX_LEN, MAX_PX / offset_width);
                debug("Clamping window height to: %f, current size: %fx%f (%fpx)",
                      new_height, offset_width, offset_height, px);
                offset_height = new_height;
            }
        } else {
            offset_height = 0;
        }

        return offset_height;
    }

    public string clean_html_markup(WebKit.WebPage page, string text, Geary.RFC822.Message message) {
        try {
            WebKit.DOM.HTMLElement html = (WebKit.DOM.HTMLElement)
                page.get_dom_document().document_element;

            // If the message has a HTML element, get its inner
            // markup. We can't just set this on a temp container div
            // (the old approach) using set_inner_html() will refuse
            // to parse any HTML, HEAD and BODY elements that are out
            // of place in the structure. We can't use
            // set_outer_html() on the document element since it
            // throws an error.
            GLib.Regex html_regex = new GLib.Regex("<html([^>]*)>(.*)</html>",
                GLib.RegexCompileFlags.DOTALL);
            GLib.MatchInfo matches;
            if (html_regex.match(text, 0, out matches)) {
                // Set the existing HTML element's content. Here, HEAD
                // and BODY elements will be parsed fine.
                html.set_inner_html(matches.fetch(2));
                // Copy email HTML element attrs across to the
                // existing HTML element
                string attrs = matches.fetch(1);
                if (attrs != "") {
                    WebKit.DOM.HTMLElement container = create(page, "div");
                    container.set_inner_html(@"<div$attrs></div>");
                    WebKit.DOM.HTMLElement? attr_element =
                        Util.DOM.select(container, "div");
                    WebKit.DOM.NamedNodeMap html_attrs =
                        attr_element.get_attributes();
                    for (int i = 0; i < html_attrs.get_length(); i++) {
                        WebKit.DOM.Node attr = html_attrs.item(i);
                        html.set_attribute(attr.node_name, attr.text_content);
                    }
                }
            } else {
                html.set_inner_html(text);
            }

            // Set dir="auto" if not already set possibly get a
            // slightly better RTL experience.
            string? dir = html.get_dir();
            if (dir == null || dir.length == 0) {
                html.set_dir("auto");
            }

            // Get all the top level block quotes and stick them into a hide/show controller.
            WebKit.DOM.NodeList blockquote_list = html.query_selector_all("blockquote");
            for (int i = 0; i < blockquote_list.length; ++i) {
                // Get the nodes we need.
                WebKit.DOM.Node blockquote_node = blockquote_list.item(i);
                WebKit.DOM.Node? next_sibling = blockquote_node.get_next_sibling();
                WebKit.DOM.Node parent = blockquote_node.get_parent_node();

                // Make sure this is a top level blockquote.
                if (Util.DOM.node_is_child_of(blockquote_node, "BLOCKQUOTE")) {
                    continue;
                }

                WebKit.DOM.Element quote_container = create_quote_container(page);
                Util.DOM.select(quote_container, ".quote").append_child(blockquote_node);
                if (next_sibling == null) {
                    parent.append_child(quote_container);
                } else {
                    parent.insert_before(quote_container, next_sibling);
                }
            }

            // Now look for the signature.
            wrap_html_signature(page, ref html);

            // Now return the whole message.
            return html.get_outer_html();
        } catch (Error e) {
            debug("Error modifying HTML message: %s", e.message);
            return text;
        }
    }

    public void unset_controllable_quotes(WebKit.WebPage page)
    throws Error {
        WebKit.DOM.HTMLElement html =
            page.get_dom_document().document_element as WebKit.DOM.HTMLElement;
        if (html != null) {
            WebKit.DOM.NodeList quote_list = html.query_selector_all(
                ".%s.%s".printf(QUOTE_CONTAINER_CLASS, QUOTE_CONTROLLABLE_CLASS)
            );
            for (int i = 0; i < quote_list.length; ++i) {
                WebKit.DOM.Element quote_container = quote_list.item(i) as WebKit.DOM.Element;
                double outer_client_height = quote_container.client_height;
                long scroll_height = quote_container.query_selector(".quote").scroll_height;
                // If the message is hidden, scroll_height will be
                // 0. Otherwise, unhide the full quote if there is not a
                // substantial amount hidden.
                if (scroll_height > 0 &&
                    scroll_height <= outer_client_height * QUOTE_SIZE_THRESHOLD) {
                    //quote_container.class_list.remove(QUOTE_CONTROLLABLE_CLASS);
                    //quote_container.class_list.remove(QUOTE_HIDE_CLASS);
                }
            }
        }
    }

    public string? get_selection_for_quoting(WebKit.WebPage page) {
        string? quote = null;
        // WebKit.DOM.Document document = page.get_dom_document();
        // WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
        // if (!selection.is_collapsed) {
        //     try {
        //         WebKit.DOM.Range range = selection.get_range_at(0);
        //         WebKit.DOM.HTMLElement dummy =
        //             (WebKit.DOM.HTMLElement) document.create_element("div");
        //         bool include_dummy = false;
        //         WebKit.DOM.Node ancestor_node = range.get_common_ancestor_container();
        //         WebKit.DOM.Element? ancestor = ancestor_node as WebKit.DOM.Element;
        //         if (ancestor == null)
        //             ancestor = ancestor_node.get_parent_element();
        //         // If the selection is part of a plain text message,
        //         // we have to stick it in an appropriately styled div,
        //         // so that new lines are preserved.
        //         if (Util.DOM.is_descendant_of(ancestor, ".plaintext")) {
        //             dummy.get_class_list().add("plaintext");
        //             dummy.set_attribute("style", "white-space: pre-wrap;");
        //             include_dummy = true;
        //         }
        //         dummy.append_child(range.clone_contents());

        //         // Remove the chrome we put around quotes, leaving
        //         // only the blockquote element.
        //         WebKit.DOM.NodeList quotes =
        //             dummy.query_selector_all("." + QUOTE_CONTAINER_CLASS);
        //         for (int i = 0; i < quotes.length; i++) {
        //             WebKit.DOM.Element div = (WebKit.DOM.Element) quotes.item(i);
        //             WebKit.DOM.Element blockquote = div.query_selector("blockquote");
        //             div.get_parent_element().replace_child(blockquote, div);
        //         }

        //         quote = include_dummy ? dummy.get_outer_html() : dummy.get_inner_html();
        //     } catch (Error error) {
        //         debug("Problem getting selected text: %s", error.message);
        //     }
        // }
        return quote;
    }

    public string? get_selection_for_find(WebKit.WebPage page) {
        string? value = null;
        // WebKit.DOM.Document document = page.get_dom_document();
        // WebKit.DOM.DOMWindow window = document.get_default_view();
        // WebKit.DOM.DOMSelection selection = window.get_selection();

        // if (selection.get_range_count() > 0) {
        //     try {
        //         WebKit.DOM.Range range = selection.get_range_at(0);
        //         value = range.get_text().strip();
        //         if (value.length <= 0)
        //             value = null;
        //     } catch (Error e) {
        //         warning("Could not get selected text from web view: %s", e.message);
        //     }
        // }
        return value;
    }

    private WebKit.DOM.HTMLElement create(WebKit.WebPage page, string name)
    throws Error {
        return page.get_dom_document().create_element(name) as WebKit.DOM.HTMLElement;
    }

    private WebKit.DOM.HTMLElement create_quote_container(WebKit.WebPage page) throws Error {
        WebKit.DOM.HTMLElement quote_container = create(page, "div");
        // quote_container.class_list.add(QUOTE_CONTAINER_CLASS);
        // quote_container.class_list.add(QUOTE_CONTROLLABLE_CLASS);
        // quote_container.class_list.add(QUOTE_HIDE_CLASS);
        // New lines are preserved within blockquotes, so this string
        // needs to be new-line free.
        quote_container.set_inner_html("""<div class="shower"><input type="button" value="▼        ▼        ▼" /></div><div class="hider"><input type="button" value="▲        ▲        ▲" /></div><div class="quote"></div>""");
        return quote_container;
    }

    private void wrap_html_signature(WebKit.WebPage page, ref WebKit.DOM.HTMLElement container) throws Error {
        // Most HTML signatures fall into one of these designs which are handled by this method:
        //
        // 1. GMail:            <div>-- </div>$SIGNATURE
        // 2. GMail Alternate:  <div><span>-- </span></div>$SIGNATURE
        // 3. Thunderbird:      <div>-- <br>$SIGNATURE</div>
        //
        WebKit.DOM.NodeList div_list = container.query_selector_all("div,span,p");
        int i = 0;
        Regex sig_regex = new Regex("^--\\s*$");
        Regex alternate_sig_regex = new Regex("^--\\s*(?:<br|\\R)");
        for (; i < div_list.length; ++i) {
            // Get the div and check that it starts a signature block and is not inside a quote.
            WebKit.DOM.HTMLElement div = div_list.item(i) as WebKit.DOM.HTMLElement;
            string inner_html = div.get_inner_html();
            if ((sig_regex.match(inner_html) || alternate_sig_regex.match(inner_html)) &&
                !Util.DOM.node_is_child_of(div, "BLOCKQUOTE")) {
                break;
            }
        }

        // If we have a signature, move it and all of its following siblings that are not quotes
        // inside a signature div.
        if (i == div_list.length) {
            return;
        }
        WebKit.DOM.Node elem = div_list.item(i) as WebKit.DOM.Node;
        WebKit.DOM.Element parent = elem.get_parent_element();
        WebKit.DOM.HTMLElement signature_container = create(page, "div");
        //signature_container.class_list.add(SIGNATURE_CONTAINER_CLASS);
        do {
            // Get its sibling _before_ we move it into the signature div.
            WebKit.DOM.Node? sibling = elem.get_next_sibling();
            signature_container.append_child(elem);
            elem = sibling;
        } while (elem != null);
        parent.append_child(signature_container);
    }

}
