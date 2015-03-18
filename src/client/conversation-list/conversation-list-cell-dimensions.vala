/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationListCellDimensions : Geary.BaseObject {
    public const string PROP_CELL_HEIGHT = "cell-height";
    public const string PROP_PREVIEW_HEIGHT = "preview-height";
    public const string PROP_VALID = "valid";
    
    /**
     * The height in pixels of each cell in the {@link ConversationListStore}.
     *
     * {@link update} ensures that the notify signal for this property is only fired when the
     * value changes.
     *
     * Defaults to -1.
     */
    public int cell_height { get; private set; default = -1; }
    
    /**
     * The height in pixels of each cell in the {@link ConversationListStore}.
     *
     * {@link update} ensures that the notify signal for this property is only fired when the
     * value changes.
     *
     * Defaults to -1.
     */
    public int preview_height { get; private set; default = -1; }
    
    /**
     * Returns true when {@link cell_height} and {@link preview_height} are valid (non-negative)
     * values.
     *
     * This does not actually check if the values are valid for screen or window dimensions, etc.
     */
    public bool valid { get; private set; default = false; }
    
    public ConversationListCellDimensions() {
    }
    
    /**
     * Update the dimensions of cells in the {@link ConversationListStore}.
     *
     * @see cell_height
     * @see preview_height
     */
    public void update(int cell_height, int preview_height) {
        // don't fire notify signal(s) until all sets are complete
        freeze_notify();
        
        if (this.cell_height != cell_height)
            this.cell_height = cell_height;
        
        if (this.preview_height != preview_height)
            this.preview_height = preview_height;
        
        valid = this.cell_height >= 0 && this.preview_height >= 0;
        
        thaw_notify();
    }
}
