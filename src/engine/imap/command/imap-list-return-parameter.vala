/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * RETURN parameters for {@link ListCommand}.
 *
 * LIST's extended syntax allows for special RETURN parameters to be included indicating additional
 * information for the server to return as part of the LIST results.  ListReturnParameters allows
 * for the well-known parameters to be easily generated and added to ListCommand.
 *
 * See the LIST-STATUS ([[https://tools.ietf.org/html/rfc5819]]) and SPECIAL-USE
 * ([[https://tools.ietf.org/html/rfc6154]]) RFCs for examples of this in use.
 */

public class Geary.Imap.ListReturnParameter : ListParameter {
    /**
     * See [[https://tools.ietf.org/html/rfc6154]]
     */
    public const string SPECIAL_USE = "special-use";

    /**
     * Creates an empty {@link ListReturnParameter}.
     *
     * If passed in without additions, this will be ignored by {@link ListCommand}.
     */
    public ListReturnParameter() {
    }

    public void add_special_use() {
        add(StringParameter.get_best_for_unchecked(SPECIAL_USE));
    }
}

