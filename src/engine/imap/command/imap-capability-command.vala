/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.1.1]]
 *
 * @see Capabilities
 */

public class Geary.Imap.CapabilityCommand : Command {
    public const string NAME = "capability";
    
    public CapabilityCommand() {
        base (NAME);
    }
}

