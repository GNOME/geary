/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailLocation : Object {
    public int position { get; private set; }
    public int64 ordering { get; private set; }
    
    private weak Geary.Folder folder;
    
    public signal void position_altered(int old_position, int new_position);
    
    public signal void position_deleted(int position);
    
    public EmailLocation(Geary.Folder folder, int position, int64 ordering) {
        assert(position >= 1);
        
        this.folder = folder;
        this.position = position;
        this.ordering = ordering;
        
        folder.message_removed.connect(on_message_removed);
    }
    
    ~EmailLocation() {
        folder.message_removed.disconnect(on_message_removed);
    }
    
    private void on_message_removed(int position, int total) {
        // if the removed position is greater than this one's, no change in this position
        if (this.position < position)
            return;
        
        // if the same, can't adjust (adjust it to what?), but notify that this EmailLocation has
        // been removed
        if (this.position == position) {
            position_deleted(position);
            
            return;
        }
        
        // adjust this position downward
        int old_position = this.position;
        this.position--;
        assert(this.position >= 1);
        
        position_altered(old_position, this.position);
    }
}

