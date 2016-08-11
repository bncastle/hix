//
//Description:
// Hix is a utility that enables compiling a Haxe source file without having a
// build.hxml file or having to specify command line args every time you want to do a build.
//
//Author: Bryan Castleberry
//Date: Jan 22,2015
//
//Command line compile to cpp: haxe -main Hix --no-traces -cpp hixcpp
//Note: The above requires you have the haxe std library dlls installed on the system
//      where you want to use Hix. That should not be a problem.
//
import sys.io.File;
import sys.FileSystem;

enum State
{
	SearchingForHeader;
	SearchingForArgs;
	FinishSuccess;
	FinishFail;
}

class Hix {
	static inline var VERSION = "0.3";
	//The header string that must be present in the file so we know to parse the compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";
	static inline var DEFAULT_BUILD_NAME = "_";
	
	//Name of the executable to run (this can be changed by placing '//::exe=newExe.exe' before the start header)
	var exe:String = "haxe";

	static function main():Int 	
	{
		if(Sys.args().length == 0 )
		{
			Sys.println('== Hix Version $VERSION by Pixelbyte Studios ==');
			Sys.println('Hix.exe <inputFile.hx> [buildName] OR');			
			Sys.println('Hix.exe -h for help');			
			return 1;
		}

		if(StringTools.startsWith(Sys.args()[0],"-h"))
		{
			Hix.PrintHelp();
			return 1;
		}

		//Get the input file name
		var inputFile:String = Sys.args()[0];
		var inputBuildName:String = DEFAULT_BUILD_NAME;

		if(Sys.args().length > 1)
			inputBuildName = Sys.args()[1];

		//Check if file exists
		if(!FileSystem.exists(inputFile))
		{
			Sys.println('[Hix] File: $inputFile does not exist!');
			return 1;
		}

		var h = new Hix();
		h.ParseFile(inputFile);

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
			if(buildName == DEFAULT_BUILD_NAME)
				Sys.println("[Hix] No compiler args found for: default");
			else
				Sys.println('[Hix] No compiler args found for: $buildName');
			return -1;
		}
		else
		{
			var args = buildMap[buildName];
			Sys.print("[Hix] Running: ");
			Sys.println(exe + " " + args.join(" "));
			Sys.println('');
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
							prevBuildName = currentBuildName;
							trace("[Hix] Header Found!");
							//Once the header is found, we begin searching for build arguments
							//Note: Once the search for build args has begun, it will stop
							//once the 1st non-comment line is reached.
							if(currentBuildName != DEFAULT_BUILD_NAME)
								trace('[Hix] Getting build args for: $currentBuildName');
							else
								trace("[Hix] Getting build args for: default");
							state = State.SearchingForArgs;
						}
						else
							//Look for any Pre-Header commmands
							ParsePreHeaderCommands();
					case State.SearchingForArgs:
						if(!inComment && currentBuildArgs.length == 0)
						{
							Sys.println("[Hix] Error: Unable to find any compiler args in the header!");
							state = State.FinishFail;
							break;
						}
						else if(!inComment && currentBuildArgs.length > 0)
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

								if(currentBuildName != DEFAULT_BUILD_NAME)
									trace("[Hix] Getting args for: " + currentBuildName);
								else
									trace("[Hix] Getting args..");
							
								CreateBuilder(prevBuildName, currentBuildArgs);
								currentBuildArgs = newArgs;
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
		//Sys.println(text);
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
			if(buildName == DEFAULT_BUILD_NAME)
				Sys.println('Error: Multiple default Build configs found.');
			else
				Sys.println('Error: Build config $buildName already exists!');
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

		if(cmd.match(text) && cmd.matched(1).indexOf('=') > -1) {
			var cmd = cmd.matched(1).toLowerCase().split('=');
			trace('[Hix] Found command: ${cmd[0]}');

			switch(cmd[0]) 
			{
				//Ah, we have found the command that says to run a different .exe
				//so change the exe to what is specified
				case "exe":
					if(cmd.length > 1 && cmd[1].length > 0)
					{
						exe = cmd[1];
						Sys.println('Hix: exe changed to: ${cmd[1]}');
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