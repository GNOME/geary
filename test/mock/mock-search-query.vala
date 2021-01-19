/*
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.SearchQuery : Geary.SearchQuery {

    internal SearchQuery(Gee.List<Geary.SearchQuery.Term> expression,
                         string raw) {
        base(expression, raw);
    }

}
