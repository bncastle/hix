package lib;

import haxe.io.Path;
import sys.FileSystem;

class Util{

	static inline var ENV_PATH = "Path";

	//Looks for and removes all boolean flags from the given array
	//and puts them into the static flags array
	public static function ParseArgOptions(args:Array<String>): Array<String>
	{
		var flags = new Array<String>();
		var i = args.length -1;
		while(i >= 0)
		{
			//A binary flag does not have an '='
			if(StringTools.startsWith(args[i],"-") && args[i].indexOf("=") == -1)
			{
				//Remove any leading.trailing spaces
				args[i] = StringTools.trim(args[i]);
				flags.push(args[i].substr(1));
				args.splice(i, 1);
			}
			i--;
		}
		return flags;
	}

	//Looks for the given string within the specified arry
	//if it is found it is removed and true is returned
	//
	public static function ProcessFlag(argName: String, args:Array<String>):Bool
	{
		var index = args.indexOf(argName);
		if(index > -1){
			args.splice(index, 1);
			return true;
		}
		return false;
	}

	//Returns the first .hx file and removes it from the array
	//returns null otherwise
	public static function GetFirstFilenameFromArgs(args:Array<String>, mustExist:Bool = true) : String
	{
		for(arg in args)
		{
			var fullName = sys.FileSystem.fullPath(arg);
			var path = new Path(arg);
			//To be considered a filename, it must have an extension
			if(path.file != null && path.ext != null && (!mustExist || sys.FileSystem.exists(fullName)))
				return arg;
		}
		return null;
	}

	//Returns the extension of a given filename
	public static function GetExt(filename:String):String{
			var path = new Path(filename);
			return path.ext;
	}

	public static function GetFilesWithExt(dir:String, ext:String):Array<String>
	{
		var files = FileSystem.readDirectory(dir);
		var filtered = files.filter(function(name)
		{
			return !FileSystem.isDirectory(name) && (ext == null || StringTools.endsWith(name, ext));
		});
		return filtered;
	}

	//Returns the 1st non-filename and removes it from the array
	//returns null, otherwise
	public static function ParseFirstNonFilename(args:Array<String>):String
	{
		var i = args.length -1;
		while(i >= 0)
		{
			var p = new Path(args[i]);
			if(p.ext == null)
			{
				var retVal = StringTools.trim(args[i]);
				args.splice(i,1);
				return retVal;
			}
			i--;
		}
		return null;
	}

	public static function FindFirstFileInDirWithExt(currentDirectory:String, ext:String) : String
	{
		//look for all files matching the given extension
		var files = GetFilesWithExt(currentDirectory, ext);
		if (files == null) return null;

		//If there is only 1 .hx file then return it
		if(files.length == 1)
			return files[0];
		else 
		{
			if(files.length > 1){
				Log.log('[Hix] Found ${files.length} files with extension ${ext}');
				return files[0];
			}
			return null;
		}
	}

	public static function FindFirstFileInValidExts(currentDirectory:String, validExts:Map<String, String>) : String
	{
        if(validExts == null) {
			Log.error("Received a null extenstion map! Aborting...");
			return null;
		}
		for(e in validExts.keys())
		{
			var filename = FindFirstFileInDirWithExt(currentDirectory, e);
			if(filename != null) return filename;
		}
		return null;
	}

	//Checks for the given file within the current environment's path string
	//returns the path (not the filename) to the file if it exists, null otherwise
	public static function WhereIsFile(filename:String):String
	{
		var pathEnv = Sys.environment()[ENV_PATH];
		if(pathEnv == null){
			Log.warn("Unable to get current environment Path!");
			return null;
		}

		//Try all the paths in the environment to see if we can find the file
		var paths = pathEnv.split(';');
		for(path in paths){
			var fullPath = Path.join([path, filename]);
			if(FileSystem.exists(fullPath)){
				trace('path for ${filename} found: ${path}');
				return path;
			}
		}
		return null;
	}

	public static function DeleteDir(path:String) : Void
	{
		if (sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path))
		{
			var entries = sys.FileSystem.readDirectory(path);
			for (entry in entries) {
				var filePath = Path.join([path,entry]);
				if (sys.FileSystem.isDirectory(filePath)) {
					DeleteDir(filePath);
					sys.FileSystem.deleteDirectory(filePath);
				} 
				else {
					sys.FileSystem.deleteFile(filePath);
				}
			}
			sys.FileSystem.deleteDirectory(path);
		}
	}
}