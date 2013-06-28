/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of one or more {@link SearchCriterion} for a {@link SearchCommand}.
 *
 * Criterion are added to the SearchCriteria one at a time with the {@link and} and {@link or}
 * methods.  Both methods return the SearchCriteria object, and so chaining can be used for
 * convenience:
 *
 * SearchCriteria criteria = new SearchCriteria();
 * criteria.is_(SearchCriterion.new_messages()).and(SearchCriterion.has_flag(MessageFlag.DRAFT));
 *
 * The or() method requires both criterion be passed:
 *
 * SearchCriteria criteria = new SearchCriteria();
 * criteria.or(SearchCriterion.old_messages(), SearchCriterion.body("attachment"));
 *
 * and() and or() can be mixed in a single SearchCriteria.
 */

public class Geary.Imap.SearchCriteria : ListParameter {
    public SearchCriteria() {
    }
    
    /**
     * Clears the {@link SearchCriteria} and sets the supplied {@link SearchCriterion} to the first
     * in the list.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria is_(SearchCriterion first) {
        clear();
        add(first.to_parameter());
        
        return this;
    }
    
    /**
     * AND another {@link SearchCriterion} to the {@link SearchCriteria}.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria and(SearchCriterion next) {
        add(next.to_parameter());
        
        return this;
    }
    
    /**
     * OR another {@link SearchCriterion} to the {@link SearchCriteria}.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria or(SearchCriterion a, SearchCriterion b) {
        add(SearchCriterion.or(a, b).to_parameter());
        
        return this;
    }
}

