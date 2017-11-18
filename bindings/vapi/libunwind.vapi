/*
 * Based on version from Sentry-GLib: https://github.com/arteymix/sentry-glib
 * Courtesy of Guillaume Poirier-Morency <guillaumepoiriermorency@gmail.com>
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
