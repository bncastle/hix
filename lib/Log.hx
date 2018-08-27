package lib;

class Log{
	public static function error(msg:Dynamic)
	{
		Sys.println('[Hix] Error: $msg');
	}

	public static function warn(msg:Dynamic)
	{
		Sys.println('[Hix] Warning: $msg');
	}

	public static function log(msg:Dynamic)
	{
		Sys.println(msg);
	}   
}