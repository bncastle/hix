//
//Description:
// Hix is a utility that enables compiling a Haxe source file without having a
// build.hxml file or having to specify command line args every time you want to do a build.
//
//Author: Bryan Castleberry
//Date: July 8,2017
//
//Command line compile to cpp: haxe -main Hix --no-traces -cpp hixcpp
//Note: The above requires you have the haxe std library dlls installed on the system
//      where you want to use Hix. That should not be a problem.
//
//::hix       -main Hix  -cpp bin --no-traces -dce full
//::hix:debug -main Hix  -cpp bin
import sys.io.File;
import haxe.io.Path;
import sys.FileSystem;

enum State
{
	SearchingForHeader;
	SearchingForArgs;
	FinishSuccess;
	FinishFail;
}

class Hix {
	static inline var VERSION = "0.38";
	//The header string that must be present in the file so we know to parse the compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";
	static inline var HX_EXT = ".hx";
	static inline var DEFAULT_BUILD_NAME = "default";
	static var VALID_EXTENSIONS = [".hx", ".cs",".js",".ts"];
	//The executable key
	static inline var EXE = "exe";

	//This is where we store any keyValue pairs we find before the hix header is found
	var keyValues:Map<String,String>;

	//Read-only property for the current state of the parser
	public var state(null,default):State = SearchingForHeader;

	//true if we are currently in a comment, false otherwise
	var inComment:Bool = false;
	
	//Tells us if we are in a multi-line comment
	var multilineComment:Bool = false;

	//The name of the file under examination
	var filename:String;

	//The current line of text from the input file
	var text:String;

	var currentBuildName:String = DEFAULT_BUILD_NAME;

	var buildMap: Map<String,Array<String>>;

	static function error(msg:Dynamic)
	{
		Sys.println('Error: $msg');
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
				error('\n** Found ${files.length} files with extension $ext. Please specify which one to use. **\n');
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
			Hix.PrintUsage();
			return 1;
		}

		//Check if file exists
		if(!FileSystem.exists(inputFile))
		{
			error('File: $inputFile does not exist!');
			return 1;
		}

		var h = new Hix();
		h.ParseFile(inputFile);

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

	public function new() 
	{
		buildMap = new Map<String,Array<String>>();
		keyValues = new Map<String,String>();

		//Set the default name of the executable to run (this can be changed by placing '//::exe=newExe.exe' before the start header)
		keyValues[EXE] = "haxe";
	}

	//
	// This executes the command that was constructed by Calling ParseFile
	//
	public function Execute(buildName: String): Int
	{
		if(!buildMap.exists(buildName) || buildMap[buildName].length == 0)
		{
			error('[Hix] No compiler args found for: $buildName');
			return -1;
		}
		else
		{
			var args:Array<String> = [];
			//Check if there are any pre args
			if (keyValues.exists("preArgs"))
			{
				args = keyValues["preArgs"].split(" ");
				log('Appending PreArgs: ${keyValues["preArgs"]}');
			}
			//Add the build args
			args = args.concat(buildMap[buildName]);

			var exe = keyValues[EXE];
			log('[Hix] Running build label: $buildName');
			log(exe + " " + args.join(" "));
			log('');
			return Sys.command(exe, args);
		}
	}

	//
	// This function parses the input file to get the command line args in order to run the haxe compiler
	//
	public function ParseFile(fileName:String)
	{
		var currentBuildArgs:Array<String> = null;
		var prevBuildName:String = DEFAULT_BUILD_NAME;
		var fileExt = "." + fileName.split(".")[1];
		inComment = false;
		multilineComment = false;
		filename = fileName;

		//Try to open the file in text mode
		var reader = File.read(fileName,false);
		try {
			trace("[Hix] Searching for a header..");
			while(true) {
				text = reader.readLine();

				//Update the multiline comment state
				CheckComment();

				switch (state)
				{
					case State.SearchingForHeader:
						currentBuildArgs = IsStartHeader();
						if(currentBuildArgs != null)
						{
							trace("[Hix] Header Found!");
							//Once the header is found, we begin searching for build arguments
							//Note: Once the search for build args has begun, it will stop
							//once the 1st non-comment line is reached.
							trace('[Hix] Getting build args for: $currentBuildName');

							state = State.SearchingForArgs;
						}
						else
							//Look for any Pre-Header commmands
							ParsePreHeaderCommands();
					case State.SearchingForArgs:
						if(!inComment && currentBuildArgs.length == 0) //Couldn't find anything
						{
							error("Unable to find any compiler args in the header!");
							state = State.FinishFail;
							break;
						}
						else if(!inComment && currentBuildArgs.length > 0) //Found something
						{
							if(fileExt != HX_EXT && keyValues[EXE] == "haxe")
							{
								error('Non-haxe src files must set executable with: //${COMMAND_PREFIX}exe=<exe_name>! Currently set to: ${keyValues[EXE]}');
								state = State.FinishFail;
							}
							else
							{
								trace("[Hix] Success");
								CreateBuilder(currentBuildName, currentBuildArgs);
								state = State.FinishSuccess;
							}
							break;
						}
						else //We're in a comment
						{
							trace("[Hix] Searching a comment");
							var newArgs = IsStartHeader();
							if(newArgs != null)
							{
								trace("[Hix] Success");
								//Since it looks like we're in a start header
								//create any builder we had previously stored
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
					case State.FinishSuccess:
					case State.FinishFail:
				}
			}
		}
		catch(ex:haxe.io.Eof) {}
		reader.close();
	}

	function ProcessSpecialCommands(buildArgList: Array<String>)
	{
		//DO any string search/replace here
		//A special string starts with '$' and can contain any chars except for whitespace
		//var sp = new EReg("^\\$([^\\s]+)", "i");
		var sp = new EReg("\\$\\[([^\\]]+)\\]", "i");
		for (i in 0...buildArgList.length) 
		{
			if(sp.match(buildArgList[i]))
			{
				//grab the special text. Split it by the '=' sign
				//so any parameters come after the =

				buildArgList[i] = sp.map(buildArgList[i], function(r){
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
							return r.matched(0); 
					}
				});
			}
		}
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

			if(!isBlank.match(header.matched(2)))
			{
				//Add this arg to our args arry and trim any whitespace
				return GrabArgs(header.matched(2));
			}
			return new Array<String>();
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
	//Look for any commands that occur BEFORE the header start sequence
	//
	function ParsePreHeaderCommands()
	{
		//If we are not in a comment, return
		if(!inComment) return;

		var cmd = new EReg(COMMAND_PREFIX + "\\s*([^\\n]*)$","i");
		var keyVal = new EReg("\\s*([A-Za-z_][A-Za-z0-9_]+)\\s*=\\s*([^\\n]+)$","i");
		if(cmd.match(text) && cmd.matched(1).indexOf('=') > -1) {
			if(keyVal.match(cmd.matched(1)))
			{
				var key = StringTools.rtrim(keyVal.matched(1));
				var val = StringTools.rtrim(keyVal.matched(2));
				trace('[Hix] Found key value pair: ${key} = ${val}');
				//Set the key value pair
				keyValues[key] = val;

				if(key == EXE)
					log('Hix: exe changed to: ${val}');
			}
		}
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
		Sys.println('Hix.exe -l <inputFile> prints valid builds');	
		Sys.println('Hix.exe -h for help');	
		Sys.println('Hix.exe -u for usage info');	
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
$[filename] -> gets the name of the current file
$[filenameNoExt] -> gets the name of the current file without the extension
$[datetime=<optional strftime format specification>] ->Note not all strftime settings are supported
$[datetime] -> without specifying a strftime format will output: %m/%e/%Y_%H:%M:%S

You can also change the program that is executed with the args (by default it is haxe)
by placing a special command BEFORE the start header:
//::exe=<name of executable>

=============================================================================
			";
			var params = {HixHeader: HEADER_START, ValidExtensions: VALID_EXTENSIONS.join(" ")};
			var template = new haxe.Template(inst);
            var output = template.execute(params);
            Sys.print(output);
	}
}