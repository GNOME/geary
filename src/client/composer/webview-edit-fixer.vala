/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Class to inject the correct blockquote-editing behavior into a WebKit.WebView.
 */
public class WebViewEditFixer {
    // HTML node names
    private const string BLOCKQUOTE_NAME = "BLOCKQUOTE";
    private const string BODY_NAME = "BODY";
    private const string BR_NAME = "BR";
    private const string DIV_NAME = "DIV";
    private const string DOCUMENT_NAME = "#document";
    private const string SPAN_NAME = "SPAN";
    private const string TEXT_NAME = "#text";

    // WebKit-specific node ids
    private const string EDITING_DELETE_CONTAINER_ID = "WebKit-Editing-Delete-Container";
    
    private WebKit.WebView web_view;
    private bool is_shift_down = false;
    
    public WebViewEditFixer(WebKit.WebView web_view) {
        this.web_view = web_view;
        this.web_view.should_insert_text.connect(on_should_insert_text);
        this.web_view.key_press_event.connect(on_key_press_event);
    }
    
    ~WebViewEditFixer() {
        web_view.should_insert_text.disconnect(on_should_insert_text);
        web_view.key_press_event.disconnect(on_key_press_event);
    }
    
    private WebKit.DOM.Document get_document() {
        return web_view.get_dom_document();
    }
    
    // We really want to examine Gdk.Keymap.get_default().get_modifier_state(), instead of storing
    // whether the shift key is down at each keypress, but it isn't yet available in the Vala
    // bindings.
    private bool on_key_press_event (Gdk.EventKey event) {
        is_shift_down = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;
        return false;
    }
    
    private bool on_should_insert_text(string text_to_insert, WebKit.DOM.Range selected_range,
        WebKit.InsertAction insert_action) {
        // We only want to intercept this event when inserting a newline.
        if (text_to_insert != "\n")
            return true;
        
        try {
            WebKit.DOM.Node start_container = selected_range.get_start_container();
            // If we are not inside a blockquote, the default behavior is fine.
            if (!has_blockquote_in_ancestry(start_container))
                return true;
            
            selected_range.delete_contents();
            
            // If the user is holding down shift, we simply insert a linebreak without splitting-
            // up the DOM (recursively or otherwise).
            long start_offset = selected_range.get_start_offset();
            if (is_shift_down)
                insert_linebreak_at_current_level(start_container, start_offset);
            else
                insert_linebreak_at_highest_level(start_container, start_offset);
            
            return false;
        } catch (Error err) {
            debug("Error in on_should_insert_text: '%s'", err.message);
            return false;
        }
    }
    
    // Checks whether node is a blockquote or has one among its ancestors.
    private bool has_blockquote_in_ancestry(WebKit.DOM.Node node) {
        WebKit.DOM.Node? current = node;
        while (current != null && current.node_name != DOCUMENT_NAME) {
            if (current.node_name == BLOCKQUOTE_NAME)
                return true;
            
            current = current.parent_node;
        }
        
        return false;
    }
    
    // Insert a linebreak without splitting up the DOM (recursively or otherwise). This method is
    // used instead of do_split when the user is holding down shift.
    private void insert_linebreak_at_current_level(WebKit.DOM.Node node, long offset) {
        try {
            WebKit.DOM.Element br = get_document().create_element(BR_NAME);
            WebKit.DOM.Node parent = node.parent_node;
            
            if (node.node_name == TEXT_NAME) {
                WebKit.DOM.Node? left, right;
                get_split_text(node, offset, out left, out right);
                if (left != null)
                    parent.insert_before(left, node);
                parent.insert_before(br, node);
                if (right != null)
                    parent.insert_before(right, node);
                parent.remove_child(node);
                
                set_focus(right ?? br, right == null ? 1 : 0);
            } else {
                WebKit.DOM.NodeList children = node.child_nodes;
                if (offset < children.length)
                    node.insert_before(br, children.item(offset));
                else
                    node.append_child(br);
                    
                set_focus(br, 1);
            }
        } catch (Error err) {
            debug("Error in insert_linebreak_at_current_level: '%s'", err.message);
        }
    }

    // Splits a text node into two halfs, with the left half containing the next before offset,
    // and the right node containing the text after offset. If either node is empty, it will be
    // null.
    private void get_split_text(WebKit.DOM.Node node, long offset, out WebKit.DOM.Node? left,
        out WebKit.DOM.Node? right) {
        WebKit.DOM.Document document = get_document();
        string node_value = node.node_value;

        // Offset is in unicode characters, but index is in bytes. We need to get the corresponding
        // byte index for the given offset.
        int char_count = node_value.char_count();
        int index = offset > char_count ? node_value.length : node_value.index_of_nth_char(offset);

        left = offset > 0 ? document.create_text_node(node_value[0:index]) : null;
        right = offset < char_count ? document.create_text_node(node_value[index:node_value.length]) : null;
    }
    
    // Focuses the cursor at the specified position.
    private void set_focus(WebKit.DOM.Node focus_node, long focus_offset = 0) {
        try {
            WebKit.DOM.DOMSelection selection = get_document().default_view.get_selection();
            selection.set_position(focus_node, focus_offset);
        } catch (Error err) {
            debug("Error in set_focus: '%s'", err.message);
        }

        scroll_into_view_if_needed(focus_node);
    }

    private void scroll_into_view_if_needed(WebKit.DOM.Node node) {
        if (node.node_value.length > 0 && node is WebKit.DOM.Element) {
            ((WebKit.DOM.Element)node).scroll_into_view_if_needed(false);
            return;
        }

        WebKit.DOM.Node? parent = node.parent_node;
        if (parent == null)
            return;

        // WebKit.DOM.Element.scroll_into_view_if_needed does not work if the element has no
        // visual component. So we create a placeholder element, scroll to that, then remove
        // the placeholder.
        try {
            WebKit.DOM.Document document = get_document();
            WebKit.DOM.Element placeholder = document.create_element(SPAN_NAME);
            WebKit.DOM.Text placeholder_text = document.create_text_node("placeholder");
            placeholder.append_child(placeholder_text);
            parent.insert_before(placeholder, node);
            placeholder.scroll_into_view_if_needed(false);
            parent.remove_child(placeholder);
        } catch (Error err) {
            debug("Error in scroll_into_view_if_needed: '%s'", err.message);
        }
    }
    
    // Recursively splits node, with 'offset' as the divider between the two halfs. Continue
    // climbing up the DOM tree, splitting as we go, until there are no more blockquotes in our
    // ancestry. When we finish recursing, insert a BR between the split nodes at the highest level
    // of the tree, and focus the BR.
    private void insert_linebreak_at_highest_level(WebKit.DOM.Node node, long offset) {
        WebKit.DOM.Node parent = node.parent_node;
        WebKit.DOM.Node? left, right;
        get_split(node, offset, out left, out right);
        
        try {
            if (has_blockquote_in_ancestry(parent)) {
                // Recursive case. Don't insert line break, and don't set focus.
                long split_offset = get_offset(parent, node);
                if (left != null) {
                    parent.insert_before(left, node);
                    split_offset++;
                }
                if (right != null)
                    parent.insert_before(right, node);
                parent.remove_child(node);
                
                insert_linebreak_at_highest_level(parent, split_offset);
            } else {
                // Base case. Insert a line break in the middle, and set the cursor focus.
                if (left != null)
                    parent.insert_before(left, node);
                WebKit.DOM.Element br = get_document().create_element(BR_NAME);
                parent.insert_before(br, node);
                if (right != null)
                    parent.insert_before(right, node);
                parent.remove_child(node);
                
                // Set the cursor focus.
                set_focus(br);
            }
        } catch (Error err) {
            debug("Error in do_split: '%s'", err.message);
        }
    }
    
    // Splits node into two halfs, one containing the children to the left of offset, the other
    // containing the children to the right of offset. If either of the split nodes has no children
    // that are neither whitespace nor a line break, null is returned for that split node.
    private void get_split(WebKit.DOM.Node node, long offset, out WebKit.DOM.Node? left,
        out WebKit.DOM.Node? right) {
        string node_name = node.node_name;
        
        if (node_name == TEXT_NAME) {
            get_split_text(node, offset, out left, out right);
            return;
        }
        
        left = node.clone_node(false);
        right = node.clone_node(false);

        // Move the first $offset children to the left node.
        for (long i = 0; i < offset; i++)
            move_first_child(node, left);
        
        // Move the remaining children to the right node.
        while (node.child_nodes.length > 0) {
            // If anything goes wrong, break out of the loop.
             if (!move_first_child(node, right))
                break;
        }
        
        if (!is_substantial(left))
            left = null;
        if (!is_substantial(right))
            right = null;
    }
    
    // Gets the number of children before child in parent's children. Child must be among parent's
    // children.
    private long get_offset(WebKit.DOM.Node parent, WebKit.DOM.Node child) {
        long offset = 0;
        WebKit.DOM.Node current = parent.child_nodes.item(offset);
        while (offset < parent.child_nodes.length) {
            if (current == null)
                break;
            if (current.is_same_node(child))
                return offset;
            
            offset++;
            current = parent.child_nodes.item(offset);
        }
        
        // Hopefully, this should never happen. But if it does, better to split in a wrong location
        // than to crash.
        return 0;
    }
    
    // Removes the first child of source and appends it to destination.
    private bool move_first_child(WebKit.DOM.Node source, WebKit.DOM.Node destination) {
        try {
            WebKit.DOM.Node temp = source.child_nodes.item(0);
            if (is_editing_delete_container(temp)) {
                source.remove_child(temp);
            } else {
                // This will remove temp from source
                destination.append_child(temp);
            }
        } catch (Error err) {
            debug("Error in move_first_child: '%s'", err.message);
            return false;
        }

        return true;
    }
    
    // There is a special node that webkit attaches to the BLOCKQUOTE in focus. We want to ignore
    // this node, as it is transient.
    private bool is_editing_delete_container(WebKit.DOM.Node node) {
        if (!node.has_attributes())
            return false;
        
        WebKit.DOM.NamedNodeMap attributes = node.get_attributes();
        WebKit.DOM.Node? id = attributes.get_named_item("id");
        return id != null && id.node_value == EDITING_DELETE_CONTAINER_ID;
    }
    
    // True if node has at least one child that is not a BR, a #text consisting entirely of
    // whitespace, or an unsubstantial div.
    private bool is_substantial(WebKit.DOM.Node node) {
        WebKit.DOM.Node child;
        for (ulong i = 0; i < node.child_nodes.length; i++) {
            child = node.child_nodes.item(i);
            if (child.node_name == BR_NAME)
                continue;
            if (child.node_name == TEXT_NAME && Geary.String.is_empty_or_whitespace(child.node_value))
                continue;
            if (child.node_name == DIV_NAME && !is_substantial(child))
                continue;
                
            return true;
        }
        
        return false;
    }
}
