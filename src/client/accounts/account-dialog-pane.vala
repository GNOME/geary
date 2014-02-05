/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Base class for account dialog panes.
// Could be factored into a generic "NotebookPage" class if needed.
public class AccountDialogPane : Gtk.Box {
    private int page_number;
    private weak Gtk.Notebook parent_notebook;
    
    public class AccountDialogPane(Gtk.Notebook parent_notebook) {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        
        this.parent_notebook = parent_notebook;
        page_number = parent_notebook.append_page(this, null);
    }
    
    public virtual void present() {
        parent_notebook.set_current_page(page_number);
    }
}

