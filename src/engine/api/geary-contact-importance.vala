/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents the relative "importance" of an occurrence of a contact in a message.
 *
 * The first word (before the underscore) indicates where the account owner appeared in the
 * message. The second word (after the underscore) indicates where the contact appeared in the
 * message.
 *
 * || "Token" || "Definition" ||
 * || FROM || appeared in the 'from' or 'sender' fields ||
 * || TO || appeared in in the 'to' field ||
 * || CC || appeared in the 'CC' or 'BCC' fields OR did not appear in any field (assuming BCC) ||
 *
 * "Examples:"
 * 
 * || "Enum Value" || "Account Owner" || "Contact" ||
 * || FROM_TO || Appeared in 'from' or 'sender' || Appeared in 'to' ||
 * || CC_FROM || Appeared in 'CC', 'BCC', or did not appear || Appeared in 'from' or 'sender'. ||
 */
public enum Geary.ContactImportance {
    FROM_FROM = 100,
    FROM_TO = 90,
    FROM_CC = 80,
    TO_FROM = 70,
    TO_TO = 60,
    TO_CC = 50,
    CC_FROM = 40,
    CC_TO = 30,
    CC_CC = 20
}
