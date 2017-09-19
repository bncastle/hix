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
	static inline var VERSION = "0.33";
	//The header string that must be present in the file so we know to parse the compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HAXE_EXTENSION = ".hx";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";
	static inline var DEFAULT_BUILD_NAME = "default";
	
	//Name of the executable to run (this can be changed by placing '//::exe=newExe.exe' before the start header)
	var exe:String = "haxe";

	//This stores any boolean flags sent as args
	static var flags:Array<String> = new Array<String>();

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
			return StringTools.endsWith(name, ext);
		});

		return filtered;
	}

	//Looks for and removes all boolean flags from the given array
	//and puts them into the static flags array
	static function ParseBooleanFlags(args:Array<String>)
	{
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
	}

	//Returns the first .hx file and removes it from the array
	//returns null otherwise
	static function ParseFirstFileFromArgs(args:Array<String>, ext:String) : String
	{
		for(arg in args)
		{
			if(StringTools.endsWith(arg, ext)) 
			{
				args.remove(arg);
				return arg;
			}
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

	static function main():Int 	
	{
		var inputFile:String = null;
		var inputBuildName:String = DEFAULT_BUILD_NAME;
		//Get the current working directory
		var cwd = Sys.getCwd();

		if(Sys.args().length == 0 )
		{
			//look for all .hx files
			var hx_files = GetFilesWithExt(cwd, HAXE_EXTENSION);

			//If there is only 1 .hx file then try that
			if(hx_files.length == 1)
				inputFile = hx_files[0];
			else 
			{
				Hix.PrintUsage();		
				return 1;
			}
		}
		else
		{
			//Get any command line args
			var args:Array<String> = Sys.args();
			//Strip any bool flags from args
			ParseBooleanFlags(args);
			//look for and .hx file specified in the args
			inputFile = ParseFirstFileFromArgs(args,HAXE_EXTENSION);
			if(inputFile == null)
			{
				//look for all .hx files
				var hx_files = GetFilesWithExt(cwd, HAXE_EXTENSION);
				//If there is only 1 .hx file then try that
				if(hx_files.length == 1)
					inputFile = hx_files[0];
				else
				{
					error('Found ${hx_files.length} $HAXE_EXTENSION files. Please specify which one to use.');
					return 1;
				}
			}
			//See if there is a build name specified
			inputBuildName = ParseFirstNonFilename(args);
			if(inputBuildName == null) inputBuildName = DEFAULT_BUILD_NAME;
		}

		//Check for any command line switches here
		if(flags.indexOf("h") > -1)
		{
			Hix.PrintHelp();
			return 1;
		}
		else if(flags.indexOf("u") > -1)
		{
			Hix.PrintUsage();
			return 1;
		}

		//Are we missing an input file?
		if(inputFile == null)
		{
			error('Unable to find a $HAXE_EXTENSION file.');
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

		if(flags.indexOf("l") > -1)
		{
			if(h.buildMap.keys().hasNext())
			{
				log('Available Build labels in: $inputFile');
				log('-----------------------');
			}
			for(buildName in h.buildMap.keys())
			{
				log('$buildName');
			}
			return 1;
		}

		if(h.state == FinishSuccess)
			return h.Execute(inputBuildName);
		else
			return 1;
	}

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

	public function new() 
	{
		buildMap = new Map<String,Array<String>>();
	}

	function Clear(arr:Array<Dynamic>)
	{
		#if (cpp || php)
			arr.splice(0, arr.length);
		#else
			untyped arr.length = 0;
		#end
	}

	//
	// This executes the command that was constructed by Calling ParseFile
	//
	public function Execute(buildName: String): Int
	{
		if(!buildMap.exists(buildName) || buildMap[buildName].length == 0)
		{
			Sys.println('[Hix] No compiler args found for: $buildName');
			return -1;
		}
		else
		{
			var args = buildMap[buildName];
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
							trace("[Hix] Success");

							CreateBuilder(currentBuildName, currentBuildArgs);
							state = State.FinishSuccess;
							break;
						}
						else //We're in a comment
						{
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
								currentBuildArgs = currentBuildArgs.concat(GrabArgs(text));
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
		var sp = new EReg("^\\$([^\\s]+)", "i");
		for (i in 0...buildArgList.length) 
		{
			if(sp.match(buildArgList[i]))
			{
				//grab the special text. Split it by the '=' sign
				//so any parameters come after the =
				var special = sp.matched(1).toLowerCase().split('=');

				//Process special commands here
				switch (special[0])
				{
					case "filename":
						buildArgList[i] = filename;
					case "datetime":
						var date = Date.now();
						//No date parameters? Ok, just do defaul Month/Day/Year
						if(special.length == 1)
							buildArgList[i] = DateTools.format(date,"%m/%e/%Y_%H:%M:%S");
						else
							buildArgList[i] = DateTools.format(date,special[1]);
				}
			}
		}
	}

	function CreateBuilder(buildName:String, args:Array<String>)
	{
		trace('Create builder for $buildName');

		if(buildMap.exists(buildName))
		{
			error('Build config $buildName already exists!');
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
				var key = keyVal.matched(1);
				var val = keyVal.matched(2);
				trace('[Hix] Found key value pair: ${key} = ${val}');
				switch (key)
				{
					//Ah, we have found the command that says to run a different .exe
					//so change the exe to what is specified
					case "exe":
						if(key.length > 1 && val.length > 0)
						{
							exe = val;
							log('Hix: exe changed to: ${val}');
						}
				}
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
		Sys.println('Hix.exe <inputFile.hx> [buildName] OR');			
		Sys.println('Hix.exe -l <inputFile.hx> prints valid builds');	
		Sys.println('Hix.exe -h for help');	
		Sys.println('Hix.exe -u for usage info');	
	}

	static function PrintHelp()
	{
var inst: String = "
Hix is a utility that lets you to store compile settings inside Haxe source files.			
Put the start header near the top of your .hx file and add desired compile args:
//$HEADER_START -main Main -neko example.n 
If you want, you can put the args on multiple lines:
//$HEADER_START
//-main Main
//-neko hi.n
Or you can put it them a multi-line comment:
/*
$HEADER_START
-main Main
-neko hi.n
*/

Hix also supports multiple build configs. Want to be able
to build either a cpp or neko target? Ok.
//$HEADER_START::target1 -main Main --no-traces -dce full -cpp bin
//$HEADER_START:::target2 -main HR --no-traces -dce full -neko hr.n

Then invoke your desired build config by adding the name of the config (which
in this case is either target1 or target2):
hix Main.hx target1 <- Builds the cpp target
hix Main.hx target2 <- Builds the neko target

Then compile by running:
hix <inputFile.hx>

No more hxml build files needed!

Special arguments:
$filename -> inserts the name of the current file into the args list
$datetime<=optional strftime format specification> ->Note not all strftime settings are supported
$datetime -> without specifying a strftime format will output: %m/%e/%Y_%H:%M:%S

You can also change the program that is executed with the args (by default it is haxe)
by placing a special command BEFORE the start header:
//::exe=<name of executable>

=============================================================================
			";
            inst = StringTools.replace(inst,"$HEADER_START", HEADER_START );
            Sys.print(inst);
	}
}