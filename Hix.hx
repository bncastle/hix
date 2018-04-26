import sys.io.File;
import haxe.io.Path;
import haxe.Json;
import sys.FileSystem;
//
//Description:
// Hix is a utility that enables compiling a Haxe source file without having a
// build.hxml file or having to specify command line args every time you want to do a build.
//
//Author: Pixelbyte studios
//Date: April 2018
//
//Note: The above requires you have the haxe std library dlls installed on the system
//      where you want to use Hix. That should not be a problem.
//
//::hix       -main Hix  -cpp bin --no-traces -dce full
//::hix:debug -main Hix  -cpp bin
//
enum State
{
	SearchingForHeader;
	SearchingForArgs;
	SearchingForOtherCommands;
	ParseEmbeddedFile;
	FinishSuccess;
	FinishFail;
}

//.c. .cpp, .cs, .hx, .js, .ts 
//comments
//	single line: //
//	multiline: /* * /

typedef KeyValue = {key: String, val: String};

class Hix {
	static inline var VERSION = "0.41";
	//The header string that must be present in the file so we know to parse the compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";
	static inline var HX_EXT = "hx";
	static inline var DEFAULT_BUILD_NAME = "default";
	static inline var OBJ_DIR = "obj";

	static var DEFAULT_CFLAGS = '/nologo /EHsc /GS /GL /Gy /sdl /O2 /WX /Fo:${OBJ_DIR}\\';
	static inline var DEFAULT_C_OUTPUT_ARGS = "${cflags} ${filename} ${defines} ${incDirs} /link /LTCG ${libDirs} ${libs} /OUT:${filenameNoExt}.exe";

	static inline var ENV_PATH = "Path";

	static var VALID_EXTENSIONS = [".hx", ".cs",".js",".ts", ".c", ".cpp"];
	static var ExtToExe:Map<String,String>= [
		"hx" => "haxe.exe",
		"cs" => "csc.exe",
		"c" => "cl.exe",
		"cpp" => "cl.exe",
		"ts" => "tsc.exe",
	];

	public static var OS = Sys.systemName();

	//The executable key
	static inline var EXE = "exe";

	//This is where we store any keyValue pairs we find before the hix header is found
	var keyValues:Map<String,String>;

	//This allows us to embed files into an existing file and hix will extract it 
	//to a temporary file for processing
	var embeddedFiles:Map<String,String>;

	//If true, then Hix will delete any generated embedded files after execution
	var deleteGeneratedEmbeddedFiles: Bool = true;

	//Read-only property for the current state of the parser
	public var state(null,default):State = SearchingForHeader;

	//true if we are currently in a comment, false otherwise
	var inComment:Bool = false;
	
	//Tells us if we are in a multi-line comment
	var multilineComment:Bool = false;

	//The name of the file under examination
	var filename:String;

	//The type of file we're looking at. I.e cs c hx js ts cpp, etc
	var fileType:String;

	//The current line of text from the input file
	var text:String;

	var currentBuildName:String = DEFAULT_BUILD_NAME;

	var buildMap: Map<String,Array<String>>;

	static function error(msg:Dynamic)
	{
		Sys.println('Error: $msg');
	}

	static function warn(msg:Dynamic)
	{
		Sys.println('Warning: $msg');
	}

	static function log(msg:Dynamic)
	{
		Sys.println(msg);
	}

	static function GetFilesWithExt(dir:String, ext:String):Array<String>
	{
		var files = FileSystem.readDirectory(dir);
		var filtered = files.filter(function(name)
		{
			return ext == null || StringTools.endsWith(name, ext);
		});

		return filtered;
	}

	//Looks for and removes all boolean flags from the given array
	//and puts them into the static flags array
	static function ParseArgOptions(args:Array<String>): Array<String>
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

	//Returns the first .hx file and removes it from the array
	//returns null otherwise
	static function GetFirstValidFileFromArgs(args:Array<String>) : String
	{
		for(arg in args)
		{
			var fullName = sys.FileSystem.fullPath(arg);
			if(sys.FileSystem.exists(fullName))
				return arg;
		}
		return null;
	}

	//Returns the 1st non-filename and removes it from the array
	//returns null, otherwise
	static function ParseFirstNonFilename(args:Array<String>):String
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

	static function FindFirstFileInDirWithExt(currentDirectory:String, ext:String) : String
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
				log('[Hix] Found ${files.length} files with extension $ext. Trying ${files[0]}');
				return files[0];
			}
			return null;
		}
	}

	static function FindFirstFileInValidExts(currentDirectory:String) : String
	{
		for(e in VALID_EXTENSIONS)
		{
			var filename = FindFirstFileInDirWithExt(currentDirectory, e);
			if(filename != null) return filename;
		}
		return null;
	}

	//Looks for the given string within the specified arry
	//if it is found it is removed and true is returned
	//
	static function ProcessFlag(argName: String, args:Array<String>):Bool
	{
		var index = args.indexOf(argName);
		if(index > -1){
			args.splice(index, 1);
			return true;
		}
		return false;
	}

	static function main():Int 	
	{
		var inputFile:String = null;
		var inputBuildName:String = DEFAULT_BUILD_NAME;

		//Get the current working directory
		var cwd = Sys.getCwd();

		if(Sys.args().length == 0 )
		{
			//look for any .hx file in the current directory
			inputFile = FindFirstFileInValidExts(cwd);
			if(inputFile == null)
			{
				PrintUsage();
				return 1;
			}
			else
				log('Trying file: $inputFile');
		}

		//Get any command line args
		var args:Array<String> = Sys.args();

		//Strip any bool flags from args
		var flags = ParseArgOptions(args);

		//Check for any command line switches here
		if(ProcessFlag("h", flags))
		{
			Hix.PrintHelp();
			return 1;
		}
		else if(ProcessFlag("u", flags))
		{
			Hix.PrintUsage();
			return 1;
		}

		//Should we not delete generatedEmbeddedFiles?
		var deleteEmbeddedFiles:Bool = !ProcessFlag("e", flags);


		//look for the first VALID filename from the args
		inputFile = GetFirstValidFileFromArgs(args);
		if(inputFile == null)
		{
			//look for any .hx file in the current directory
			inputFile = FindFirstFileInValidExts(cwd);
			if(inputFile == null)
			{
				PrintUsage();
				return 1;
			}
			else
				log('Trying file: $inputFile');
		}

		//See if there is a build name specified
		inputBuildName = ParseFirstNonFilename(args);
		if(inputBuildName == null) inputBuildName = DEFAULT_BUILD_NAME;

		//Are we missing an input file?
		if(inputFile == null)
		{
			error('Unable to find any valid files!');
			return 1;
		}

		//Check if file exists
		if(!FileSystem.exists(inputFile))
		{
			error('File: $inputFile does not exist!');
			return 1;
		}

		var h = new Hix(deleteEmbeddedFiles);
		h.ParseFile(inputFile);

		if(ProcessFlag("clean", flags)){
			if(h.fileType == "c" || h.fileType == "cpp"){
				if(FileSystem.exists(OBJ_DIR)){
					log('[Hix] Cleaning ${OBJ_DIR} directory');
					DeleteDir(OBJ_DIR);
				}
				else{
					log('[Hix] No ${OBJ_DIR} directory exists');
				}
			}
			else{
				log('[Hix] Currently only supports cleaning for .c and .cpp files.');
			}
			return 1;
		}

		if(ProcessFlag("l", flags))
		{
			if(h.buildMap.keys().hasNext())
			{
				log('Available Build labels in: $inputFile');
				log('-----------------------');
				for(buildName in h.buildMap.keys())
				{
					log('$buildName');
				}
			}
			else
			{
				error('No build instructions found in: $inputFile');
			}
			return 1;
		}

		if(h.state == FinishSuccess){
			trace("File successfully parsed. Executing...");
			return h.Execute(inputBuildName);
		}
		else if(h.state == SearchingForHeader){
			error("Unable to find a hix header!");
			return 1;
		}
		else{
			trace('Parser State: ${h.state}');
			error("There was a problem!");
			return 1;
		}
	}

	public function new(deleteGeneratedFiles:Bool = true) 
	{
		buildMap = new Map<String,Array<String>>();
		keyValues = new Map<String,String>();
		embeddedFiles = new Map<String,String>();
		deleteGeneratedEmbeddedFiles = deleteGeneratedFiles;

		//Setup some defaults for C/C++ builds
		keyValues["cflags"] = DEFAULT_CFLAGS;
	}

	//
	// This executes the command that was constructed by Calling ParseFile
	//
	public function Execute(buildName: String): Int
	{
		var embeddedFilesUsed: Array<String> = new Array<String>();
	
		if(!buildMap.exists(buildName) || buildMap[buildName].length == 0)
		{
			error('[Hix] No compiler args found for: $buildName');
			return -1;
		}
		else
		{
			var exe:String = keyValues[EXE];
			if(exe == null || exe.length == 0){
				error('Exe is unknown or was not specified using //::exe\nExiting...');
				return -1;
			}

			var args:List<String> = new List<String>();
			//Check if there are any pre args
			if (keyValues.exists("preCmd"))
			{
				log('Appending PreCmd: ${keyValues["preCmd"]}');
				args.add(keyValues["preCmd"]);
			}

			//Do special things for certain filetypes
			//create an obj folder for .c or cpp files if one doesn't exist
			if(fileType == "c" || fileType == "cpp" ){
				if(!FileSystem.exists(OBJ_DIR))
					FileSystem.createDirectory(OBJ_DIR);
			}

			//See if the EXE is in the filepath AND if we have a setupEnv key/value pair
			//If the exe can't be found, assume that the environment needs to be setup by calling 
			//whatever the setupEnv command is
			if(WhereIsFile(exe) == null){
				var exePath = Config.Get(exe + "Path");
				if(exePath != null){
					// Sys.environment()[ENV_PATH] = Sys.environment()[ENV_PATH] + ";" + exePath;
					exe = Path.join([exePath, exe]);
				}
				if(keyValues.exists("setupEnv")){
					args.add(keyValues["setupEnv"] + "&&");
					//Sys.command(keyValues["setupEnv"]);
					//Config.Save({key : exe + "Path", val : WhereIsFile(exe)});
				}
				else{
					error('Unable to find the executable: ${exe}');
					return -1;
				}
			}

			//Add the actual command
			args.add(exe);

			//Add the build args
			for(a in buildMap[buildName])
				args.add(a);

			for (text in args){
				//Windows filenames are case insensitive
				if(OS == "Windows") text = text.toLowerCase();

				//search for any embedded files in the args and if found, create them and add them to a list
				//to be deleted after the run is finished
				for(filename in embeddedFiles.keys()){
					//Skip any that we already know are used
					if(embeddedFilesUsed.indexOf(filename) > -1) continue;
					
					//Is this file referenced?
					if(text.indexOf(filename) > -1){
						//Does it already exist?
						if(FileSystem.exists(filename)){
							warn('Embedded file: ${filename} already exists. Ignoring embedded version.');
						}
						//If not, create the file
						else{
							trace('[Hix] creating embedded file: ${filename}');
							File.saveContent(filename, embeddedFiles[filename]);
							embeddedFilesUsed.push(filename);
						}
					}
				}
			}

			log('[Hix] Running build label: $buildName');
			log(args.join(" ") + "\n");
			var retCode = Sys.command(args.join(" "));
			//var retCode = Sys.command(exe, args);

			//Delete any temp-create embedded files
			if(embeddedFilesUsed.length > 0){
				if(deleteGeneratedEmbeddedFiles){
					log('[Hix] cleaning up embedded files.');
					for(filename in embeddedFilesUsed){
						try{
							FileSystem.deleteFile(filename);
						}
						catch(ex:Dynamic) { 
							error('Unable to delete embedded file: ${filename}!');
						}
					}
				}
				else{
					log('[Hix] NOT cleaning up embedded files.');
				}
			}
			return retCode;
		}
	}

	//
	// This function parses the input file to get the command line args in order to run the haxe compiler
	//
	public function ParseFile(fileName:String)
	{
		var endMultilineComment =  ~/^\s*\*\//;
		var whitespace= ~/^\s+$/g;
		var currentBuildArgs:Array<String> = null;
		var prevBuildName:String = DEFAULT_BUILD_NAME;
		fileType = fileName.split(".")[1].toLowerCase();

		//Set the default name of the executable to run (this can be changed by placing '//::exe=newExe.exe' before the start header)
		if(ExtToExe.exists(fileType))
			keyValues[EXE] = ExtToExe[fileType]
		else
			keyValues[EXE] = "";

		//What line are we on
		var line = -1;
		//Store the name of the embedded file we are curently parsing (if there are any) in here
		var embeddedFilename:String ="";
		var fileContents: StringBuf = null;

		inComment = false;
		multilineComment = false;
		filename = fileName;

		//Try to open the file in text mode
		var reader = File.read(fileName,false);
		try {
			trace("[Hix] Searching for a header..");
			while(true) {
				text = reader.readLine();
				line++;

				//Update the multiline comment state
				CheckComment();

				switch (state) {
					case State.SearchingForHeader:
						currentBuildArgs = IsStartHeader();
						if(currentBuildArgs != null) {
							trace("[Hix] Header Found!");
							//Once the header is found, we begin searching for build arguments
							//Note: Once the search for build args has begun, it will stop
							//once the 1st non-comment line is reached.
							trace('[Hix] Getting build args for: $currentBuildName');

							state = State.SearchingForArgs;
						}
						else {
							//Look for any Pre-Header key/values
							var t = ParsePreHeaderKeyValue();
							if(t != null)
							{
								keyValues[t.key] = t.val;
								if(t.key == EXE)
									log('[Hix] exe changed to: ${t.val}');
								else if(t.key == "incDirs"){
									var v = t.val.split(" ");
									v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
									if(v.length == 0) keyValues[t.key] = "";
									else{
										v[0] = "/I" + v[0];
										keyValues[t.key] = v.join(" /I");
									}
								}
								else if(t.key == "libDirs"){
									var v = t.val.split(" ");
									v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
									if(v.length == 0) keyValues[t.key] = "";
									else{
										v[0] = "/LIBPATH:" + v[0];
										keyValues[t.key] = v.join(" /LIBPATH:");
									}
								}
								else if(t.key == "defines"){
									var v = t.val.split(" ");
									v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
									if(v.length == 0) keyValues[t.key] = "";
									else{
										v[0] = "/D" + v[0];
										keyValues[t.key] = v.join(" /D");
									}
								}
								else if(t.key == "libs"){
									var v = t.val.split(" ");
									v = v.filter(function(str) return str.length > 0 && !whitespace.match(str));
									if(v.length == 0) keyValues[t.key] = "";
									else{
										keyValues[t.key] = v.map(function(str) {
											if(str.indexOf(".") > -1) return str;
											else return str + ".lib";
										}).join(" ");
									}
								}
							}
						}

					case State.SearchingForArgs:
						if(!inComment && currentBuildArgs.length == 0) //Couldn't find anything
						{
							error("Unable to find any compiler args in the header!");
							state = State.FinishFail;
							break;
						}
						else if(!inComment && currentBuildArgs.length > 0) //Found something
						{
							trace("[Hix] Success. Found compiler args");
							CreateBuilder(currentBuildName, currentBuildArgs);
							// state = State.FinishSuccess;
							state = SearchingForOtherCommands;
							trace("[Hix] Searching for other commands");
							// break;
						}
						else //We're in a comment
						{
							trace("[Hix] Searching a comment");
							var newArgs = IsStartHeader();
							if(newArgs != null)
							{
								trace("[Hix] Success");
								//Since it looks like we're in a start header, create any builder we had previously stored
								CreateBuilder(prevBuildName, currentBuildArgs);
								//Now switch to this new current one
								currentBuildArgs = newArgs;
								prevBuildName = currentBuildName;

								trace("[Hix] Getting args for: " + currentBuildName);
							}
							else
							{
								//we are in a comment, lets see if there is text here if there is we assume it is a command arg
								//If, however, the comment is empty, then move on
								var grabbedArgs = GrabArgs(text);
								if(grabbedArgs != null && grabbedArgs.length > 0)
									currentBuildArgs = currentBuildArgs.concat(grabbedArgs);
								// else{
								// 	error('Unable to grab args. Offending text:\n${text}');
								// 	state = State.FinishFail;
								// }
							}
						}
					case State.SearchingForOtherCommands:
						if(inComment)
						{
							//Look for any other keyvalue commands
							var t = ParsePreHeaderKeyValue();
							if(t != null)
							{
								trace('key: ${t.key}');
								if(t.key=="tmpfile")
								{
									if(t.val =="" || t.val==null)
									{
										error('[Hix: ${line}] Must specify a name for the embedded file!');
										state = State.FinishFail;
									}
									else{
										log('[Hix] embedded file found: ${t.val}');
										if(OS == "Windows") 
											embeddedFilename = t.val.toLowerCase();
										else
											embeddedFilename = t.val;
										state = State.ParseEmbeddedFile;
										fileContents = new StringBuf();
									}
								}
							}
						}
					case State.ParseEmbeddedFile:
						if(!inComment){
							if(fileContents.length > 0){
								embeddedFiles.set(embeddedFilename, fileContents.toString());
								fileContents = null;
							}
							state = State.SearchingForOtherCommands;
						}
						else
						{
							//Make sure this is NOT the end of a multiline comment
							//The multiline comment ending tag '*/' must be placed on a separate line
							if(!endMultilineComment.match(text)){
								if(fileContents.length > 0)
									fileContents.add("\n");
								fileContents.add(Std.string(text));
							}
						}
					case State.FinishSuccess:
					case State.FinishFail:
				}
			}
		}
		catch(ex:haxe.io.Eof) { }

		if(fileContents != null && fileContents.length > 0){
		 	embeddedFiles.set(embeddedFilename, fileContents.toString());
		}
		if (state == State.ParseEmbeddedFile || state == State.SearchingForOtherCommands)
		 	state = State.FinishSuccess;

		reader.close();
	}

	function ProcessSpecialCommands(buildArgList: Array<String>)
	{
		for (i in 0...buildArgList.length) 
		{
			buildArgList[i] = ProcessSpecialCommand(buildArgList[i]);
		}
	}

	//DO any string search/replace here
	//A special string starts with '$' and can contain any chars except for whitespace
	//var sp = new EReg("^\\$([^\\s]+)", "i");
	var sp = new EReg("\\${([^\\]]+)}", "i");

	function ProcessSpecialCommand(text:String, key:String = null, returnEmptyIfNotFound:Bool = false):String{
		if(sp.match(text))
		{
			//grab the special text. Split it by the '=' sign
			//so any parameters come after the =

			text = sp.map(text, function(r){
				var matched = r.matched(1);
				//Process special commands here
				switch (matched)
				{
					case "filename":return filename;
					//Filename without the extension
					case "filenameNoExt":return filename.split(".")[0];
					case "datetime":
						var date = Date.now();
						var cmd = matched.split('=');
						//No date parameters? Ok, just do defaul Month/Day/Year
						if(cmd.length == 1)
							return DateTools.format(date,"%m/%e/%Y_%H:%M:%S");
						else
							return DateTools.format(date,cmd[1]);
					default:
						if(keyValues.exists(matched)){
							if(matched == key){
								error('Recursive key reference detected: ${key}');
							return r.matched(0);
							}
							else
								return keyValues.get(matched);
						}
						else{
							if(returnEmptyIfNotFound)
								return "";
							else
								return r.matched(0);
						}
				}
			});
		}
		return text;
	}

	function CreateBuilder(buildName:String, args:Array<String>)
	{
		trace('Create builder for $buildName\n');

		if(buildMap.exists(buildName))
		{
			error('Found duplicate build name: $buildName in $filename!');
			state = State.FinishFail;
			return;
		}

		//Now process any special commands
		ProcessSpecialCommands(args);

		//Add this map to our list of build configs
		buildMap[buildName] = args;
	}

	//Looks for the start header string
	//returns: null if no header found or a new args array
	//
	function IsStartHeader():Array<String>
	{
		//If we are not in a comment, return
		if(!inComment) return null;

		var header = new EReg(HEADER_START + "(:\\w+)?\\s*([^\\n]*)$","i");

		//See if there is any stuff after the header declaration
		if(header.match(text))
		{
			var isBlank = ~/^\s*$/;
			
			//Did we find a buildName?
			if(!isBlank.match(header.matched(1)) && header.matched(1).length > 1)
				currentBuildName = header.matched(1).substr(1);
			else 
				currentBuildName = DEFAULT_BUILD_NAME;

			if(!isBlank.match(header.matched(2))){
				//Add this arg to our args arry and trim any whitespace
				return GrabArgs(StringTools.rtrim(header.matched(2)));
			}
			else{
				trace('[Hix] Unable to find args for ${currentBuildName}');
				if(fileType == "c" || fileType == "cpp"){
					trace('[Hix] Settings default args for .c|.cpp file for ${currentBuildName}:\n${DEFAULT_C_OUTPUT_ARGS}');
					return GrabArgs(DEFAULT_C_OUTPUT_ARGS);
				}
				else{
					trace('[Hix] Args were empty and no default args found for ${currentBuildName}');
					return new Array<String>();
				}
			}
		}
		return null;
	}


	//Grabs the compiler arguments from the given text
	//
	function GrabArgs(txt:String): Array<String> 
	{
		var isBlank = ~/\s*^\/*\s*$/;

		if(isBlank.match(txt)) return null;
		var args:Array<String> = new Array<String>();

		var remhdr = new EReg("^\\s*" + HEADER_START,"i");
		var remcomm = ~/\s*\/\//;
		txt = remcomm.replace(txt,"");
		txt = remhdr.replace(txt,"");
		txt = StringTools.trim(txt);

		var parsedArgs = ParseSepString(txt, " ");
		for(a in parsedArgs)
		{
			args.push(a);
		}

		if(args.length > 0)
			return args;
		else 
			return null;
	}

	//
	//Look for any key value declarations that occur BEFORE the header start sequence
	//
	function ParsePreHeaderKeyValue() : KeyValue
	{
		//If we are not in a comment, return
		if(!inComment) return null;
		var cmd = new EReg(COMMAND_PREFIX + "\\s*([^\\n]*)$","i");
		var keyVal = new EReg("\\s*([A-Za-z_][A-Za-z0-9_]+)\\s*=\\s*([^\\n]+)$","i");
		if(cmd.match(text) && cmd.matched(1).indexOf('=') > -1) {
			if(keyVal.match(cmd.matched(1)))
			{
				var key = StringTools.rtrim(keyVal.matched(1));
				var val = ProcessSpecialCommand(StringTools.rtrim(keyVal.matched(2)), key);
				trace('[Hix] Found key value pair: ${key} = ${val}');
				return {key: key, val: val};
			}
			else 
				return null;
		}
		else
			return null;
	}

	//Looks for single and multi-line comments
	//
	function CheckComment() 
	{
		//Check for a line comment with nothing but optional spaces before it starts
		var singleComment = ~/^\s*\/\//;
		//2 different ways of instantiating an EReg
		var begin = new EReg("/\\*","i");
		var end = ~/\*\//;

		//if we weren't in a comment, see if we are now
		//Otherwise see if we are out of the comment
		if(!multilineComment)
		{
			multilineComment = begin.match(text) && !end.match(text);

			//See if we have a line comment
			inComment = begin.match(text) || singleComment.match(text);
		}
		else
		{
			multilineComment = !end.match(text);

			//even if the multiline comment ends, this line is still a comment
			inComment = true;
		}
	}

	//
	//This parses a string separated by the given delim and deals with quoted values
	//
	static function ParseSepString(text:String, delim:String, removeQuotes:Bool = true) : Array<String> 
	{
	    var cols:Array<String> = new Array<String>();
	    var start = 0;
	    text = StringTools.trim(text);
	    var end = text.length;
	    while(start < end)  {
	         if(text.charAt(start) == '"') //Quoted value
	         {
	              var endQuote = text.indexOf('"', start + 1);
	              if(endQuote == -1)
	                   throw("[Hix] Parse Error: Expected a matching \"" + text);
	              else if(text.charAt(endQuote + 1) == '"')
				  {
	              	endQuote++;
	              	endQuote = text.indexOf('"', endQuote + 1);

					while(text.charAt(endQuote + 1) == '"')
						endQuote++;
	              }

	              if(removeQuotes)
				  {
	              	cols.push(text.substr(start + 1, endQuote - (start + 1)));
	              	//trace("[Hix] DQ: " + text.substr(start + 1, endQuote - (start + 1)));
				  }
				  else
				  {
	              	cols.push(text.substr(start, endQuote + 1 - start));
	              	//trace("[Hix] DQ: " + text.substr(start , endQuote - start));
				  }
	              start = endQuote + 1;
	         }
	         else if(text.charAt(start) == "'") {//Single Quote value
	              var endQuote = text.indexOf("'", start + 1);

	              if(endQuote == -1)
	                   throw("[Hix] Parse Error: Expected a matching '\n" + text);

	              if(removeQuotes) 
				  {
		              cols.push(text.substr(start + 1, endQuote - (start + 1)));
		              //trace("[Hix] Q: " + text.substr(start + 1, endQuote - (start + 1)));
	          	  }
	          	  else 
				  {
		              cols.push(text.substr(start, endQuote + 1 - start));
		              //trace("[Hix] Q: " + text.substr(start, endQuote - start ));
	          	  }

	              start = endQuote + 1;
	         }
	         else if(text.charAt(start) == " " )
	         	start++;
	         else if(text.charAt(start) == delim)  
			 {
	              start++;
	              //Check and see if it is a null value
	              while(start < end && text.charAt(start) == " ") start++;
	              if(text.charAt(start) == delim)
	              {
	              	//An empty column
	              	//cols.push("");
	              }
	         }
	         else 
			 {
	              var lastChar = text.indexOf(delim, start);
	              if(lastChar == -1)
	                   lastChar = end;
	              if(lastChar - start > 0)  
				  {
	                   cols.push(text.substr(start, lastChar - start));
	                   //trace(text.substr(start, lastChar - start));
	                   start = lastChar;
	              }
	         }
	    }
	    return cols;
	}

	public function PrintValidBuilds()
	{
		Sys.println("Valid Builds");
		Sys.println("============");
		for(key in buildMap.keys()){
			Sys.println(key);
		}
	}

	static function PrintUsage()
	{
		Sys.println('== Hix Version $VERSION by Pixelbyte Studios ==');
		Sys.println('Hix.exe <inputFile> [buildName] OR');			
		Sys.println('available flags:');
		Sys.println('-clean Cleans any intermediate files (currently for .c and .cpp src files only)');
		Sys.println('-l <inputFile> prints valid builds');
		Sys.println('-e Tells hix not to delete generated embeded files after build completion');
		Sys.println('-h prints help');
		Sys.println('-u prints usage info');	
	}

	static function PrintHelp()
	{
var inst: String = "
 Hix is a utility that lets you to store compile settings inside of source files.
 Currently supported languages are: ::ValidExtensions::	
 Put the start header near the top of your source file and add desired compile args:
 //::HixHeader:: -main Main -neko example.n 
 If you want, you can put the args on multiple lines:
 //::HixHeader::
 //-main Main
 //-neko hi.n
 Or you can put it them a multi-line comment:
 /*
 ::HixHeader::
 -main Main
 -neko hi.n
 */
 
 Hix also supports multiple build configs.
 For example, in a haxe .hx file you can specify both cpp and neko target builds. 
 
 //::HixHeader:::target1 -main Main --no-traces -dce full -cpp bin
 //::HixHeader:::target2 -main HR --no-traces -dce full -neko hr.n
 
 Then invoke your desired build config by adding the name of the config (which
 in this case is either target1 or target2):
 hix Main.hx target1 <- Builds target1
 hix Main.hx target2 <- Builds target2
 
 Then compile by running:
 hix <inputFile>
 
 No more hxml or makefiles needed!
 
 Special arguments:
 ${filename} -> gets the name of the current file
 ${filenameNoExt} -> gets the name of the current file without the extension
 ${datetime} -> <optional strftime format specification>] ->Note not all strftime settings are supported
 ${datetime} -> without specifying a strftime format will output: %m/%e/%Y_%H:%M:%S
 
 You can also change the program that is executed with the args (by default it is haxe)
 by placing a special command BEFORE the start header:
 //::exe=<name of executable>

 Additionally, hix also supports embedded files:
 /*::tmpfile= [filename]
 file contents
 */
 Any build tasks referring to this filename will cause it to be created before executing the build
 After the build has completed, the file will be deleted unless the '-e' flag is specified
 
 =============================================================================
			";
			var params = {HixHeader: HEADER_START, ValidExtensions: VALID_EXTENSIONS.join(" ")};
			var template = new haxe.Template(inst);
            var output = template.execute(params);
            Sys.print(output);
	}

	//Checks for the given file within the current environment's path string
	//returns the path (not the filename) to the file if it exists, null otherwise
	public static function WhereIsFile(filename:String):String
	{
		var pathEnv = Sys.environment()[ENV_PATH];
		if(pathEnv == null){
			warn("Unable to get current environment Path!");
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

class Config{
	static inline var CFG_FILE = "hix.json";
	static var cfgPath = Path.join([Path.directory(Sys.programPath()), CFG_FILE]);

	public static function Save(kv:KeyValue){
		var keyValues:Map<String,String> = null;
		if(!FileSystem.exists(cfgPath))
			keyValues = new	Map<String, String>();
		else{
			var text = File.getContent(cfgPath);
			keyValues = Json.parse(text);
		}
	
		if(kv.val == null || kv.val.length == 0)
			keyValues.remove(kv.key);
		else
			keyValues[kv.key] = kv.val;
		
		//Only save it if there is at least one key in the keyValues map
		if(keyValues.keys().hasNext())
			File.saveContent(cfgPath, Json.stringify(keyValues));
	}

	public static function Get(key:String):String{
		if(!FileSystem.exists(cfgPath))
			return null;
		else{
			var text = File.getContent(cfgPath);
			var keyValues:Map<String,String> = Json.parse(text);
			if(keyValues.exists(key))
				return keyValues[key];
			else
				return null;
		}
	}
}