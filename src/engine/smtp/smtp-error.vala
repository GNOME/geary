/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public errordomain Geary.SmtpError {
    PARSE_ERROR,
    STARTTLS_FAILED,
    AUTHENTICATION_FAILED,
    SERVER_ERROR,
    ALREADY_CONNECTED,
    NOT_CONNECTED,
    REQUIRED_FIELD
}

