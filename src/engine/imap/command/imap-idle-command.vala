/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc2177]]
 *
 * @see NoopCommand
 */

public class Geary.Imap.IdleCommand : Command {
    public const string NAME = "idle";
    
    public IdleCommand() {
        base (NAME);
    }
}

