/*
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A set of quirks for a specific IMAP service.
 */
public class Geary.Imap.Quirks : BaseObject {


    /** The set of additional characters allowed in an IMAP flag. */
    public string? flag_atom_exceptions { get; set; }

    /**
     * The maximum number of commands that will be pipelined at once.
     *
     * If 0 (the default), there is no limit on the number of
     * pipelined commands sent to this endpoint.
     */
    public uint max_pipeline_batch_size { get; set; default = 0; }


}
