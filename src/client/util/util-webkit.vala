/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

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

