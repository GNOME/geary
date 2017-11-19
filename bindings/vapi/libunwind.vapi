/*
 * Based on version from Sentry-GLib: https://github.com/arteymix/sentry-glib
 * Courtesy of Guillaume Poirier-Morency <guillaumepoiriermorency@gmail.com>
 *
 * Copyright (C) 1996 X Consortium
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE X CONSORTIUM BE LIABLE FOR
 * ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 * CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Except as contained in this notice, the name of the X Consortium
 * shall not be used in advertising or otherwise to promote the sale,
 * use or other dealings in this Software without prior written
 * authorization from the X Consortium.
 *
 * X Window System is a trademark of X Consortium, Inc.
 */

[CCode (cprefix = "UNW_", lower_case_cprefix = "unw_", cheader_filename = "libunwind.h")]
namespace Unwind
{

	[CCode (cname = "unw_context_t")]
	public struct Context
	{
		[CCode (cname = "unw_getcontext")]
		public Context ();
	}

	[CCode (cname = "unw_proc_info_t")]
	public struct ProcInfo
	{
		void* start_ip;
		void* end_ip;
		void* lsda;
		void* handler;
		void* gp;
		long flags;
		int format;
	}

	[CCode (cname = "unw_frame_regnum_t")]
	public enum Reg
	{
		IP,
		SP,
		EH
	}

	[CCode (cname = "unw_cursor_t", cprefix = "unw_")]
	public struct Cursor
	{
		public Cursor.local (Context ctx);
		public int get_proc_info (out ProcInfo pip);
		public int get_proc_name (uint8[] bufp, out long offp = null);
		public int get_reg (Reg reg, out void* valp);
		public int step ();
	}

    [CCode (cname = "unw_error_t", cprefix = "UNW_E", has_type_id = false)]
    public enum Error
    {
        SUCCESS,
        UNSPEC,
        NOMEM,
        BADREG,
        READONLYREG,
        STOPUNWIND,
        INVALIDIP,
        BADFRAME,
        INVAL,
        BADVERSION,
        NOINFO
    }

}
