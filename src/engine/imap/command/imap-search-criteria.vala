/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of one or more {@link SearchCriterion} for a {@link SearchCommand}.
 *
 * Criterion are added to the SearchCriteria one at a time with the {@link and}, {@link or}, and/or
 * {@link not} methods.  Both methods return the SearchCriteria object, and so chaining can be used
 * for convenience:
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
    public SearchCriteria(SearchCriterion? first = null) {
        if (first != null)
            add_all(first.to_parameters());
    }

    /**
     * Clears the {@link SearchCriteria} and sets the supplied {@link SearchCriterion} to the first
     * in the list.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria is_(SearchCriterion first) {
        clear();
        add_all(first.to_parameters());

        return this;
    }

    /**
     * AND another {@link SearchCriterion} to the {@link SearchCriteria}.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria and(SearchCriterion next) {
        add_all(next.to_parameters());

        return this;
    }

    /**
     * OR two {@link SearchCriterion}s to the {@link SearchCriteria}.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria or(SearchCriterion a, SearchCriterion b) {
        add_all(SearchCriterion.or(a, b).to_parameters());

        return this;
    }

    /**
     * NOT another {@link SearchCriterion} to the {@link SearchCriteria}.
     *
     * @return This SearchCriteria for chaining.
     */
    public unowned SearchCriteria not(SearchCriterion next) {
        add_all(SearchCriterion.not(next).to_parameters());

        return this;
    }
}

