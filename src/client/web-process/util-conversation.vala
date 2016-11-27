/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Util.Conversation {

    private const string QUOTE_CONTAINER_CLASS = "geary_quote_container";
    private const string QUOTE_CONTROLLABLE_CLASS = "controllable";
    private const string QUOTE_HIDE_CLASS = "hide";
    private const float QUOTE_SIZE_THRESHOLD = 2.0f;


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

}
