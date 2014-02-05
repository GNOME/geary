/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// An ordered grouping meant to go alongside special folders in the account
// branch.
public class FolderList.SpecialGrouping : Sidebar.Grouping {
    // Must be != 0 and unique among SpecialGroupings.  Bigger comes later
    // in the list.  If < 0, it comes before non-SpecialGroupings.
    public int position { get; private set; }
    
    public SpecialGrouping(int position, string name, Icon? open_icon,
        Icon? closed_icon = null, string? tooltip = null) {
        base(name, open_icon, closed_icon, tooltip);
        
        this.position = position;
    }
}
