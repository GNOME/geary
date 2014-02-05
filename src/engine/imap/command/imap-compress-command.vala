/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc4978]]
 */

public class Geary.Imap.CompressCommand : Command {
    public const string NAME = "compress";
    
    public const string ALGORITHM_DEFLATE = "deflate";
    
    public CompressCommand(string algorithm) {
        base (NAME, { algorithm });
    }
}

