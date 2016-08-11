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
//Or run it as a script: haxe -main Hix --interp Hix.hx

import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

enum State
{
	SearchingForHeader;
	GettingArgs;
	FinishSuccess;
	FinishFail;
}


class Hix {
	static inline var VERSION = "0.3";

	//Name of the executable to run
	//Note this can be changed by the 'exe' command
	var exe:String = "haxe";

	//This is the header string that must be present in the file to allow us to parse the
	//compiler args
	static inline var COMMAND_PREFIX = "::";
	static inline var HEADER_START = COMMAND_PREFIX + "hix";
	static inline var SPECIAL_CHAR = "$";

	static function main():Int 	{
		if(Sys.args().length == 0 ) {
			Sys.println('== Hix Version $VERSION by Pixelbyte Studios ==');
			Sys.println('Hix.exe <inputFile.hx> OR');			
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

		//Check if file exists
		if(!FileSystem.exists(inputFile))	{
			Sys.println('[Hix] File: $inputFile does not exist!');
			return 1;
		}

		var h = new Hix();
		var args = h.ParseFile(inputFile);

		if(!h.Execute()) return 1;
		else return 0;
	}

	//The Path of this exe
	var exePath:String;

	var args:Array<String>;

	//Read-only property for the current state of the parser
	public var state(null,default):State = SearchingForHeader;

	//true if we are currently in a comment, false otherwise
	var isAComment:Bool = false;

	//The current line of text from the input file
	var text:String;

	public function new() {
		args = new Array<String>();

		//Get the pateh where this executable resides
		exePath = Sys.programPath();
		if(exePath.charAt(exePath.length - 1) == '/')
			exePath = exePath.substr(0,exePath.length - 1);
		exePath = Path.addTrailingSlash(exePath);
	}

	function Clear(arr:Array<Dynamic>){
		#if (cpp || php)
			arr.splice(0, arr.length);
		#else
			untyped arr.length = 0;
		#end
	}

	//
	// This executes the command that was constructed by Calling ParseFile
	//
	public function Execute(): Bool
	{
		if(state == State.SearchingForHeader) {
			Sys.println('[Hix] Unable to find the start header in a comment block -> $HEADER_START');
			return false;
		}
		else if(args.length == 0) {
			Sys.println("[Hix] No compiler args found!");
			return false;
		}
		else {
			Sys.print("[Hix] Running: ");
			Sys.println(exe + " " + args.join(" "));
			Sys.println('');
			return Sys.command(exe, args) == 0;
		}
	}

	//
	// This function parses the input file to get the command line args in order to run the haxe compiler
	//
	public function ParseFile(fileName:String): Array<String> {

		//Clear all state info
		Clear(args);
		isAComment = false;
		inMultiLineComment = false;

		//Try to open the file in text mode
		var reader = File.read(fileName,false);
		try {
			trace("Searching for a header..");
			while(true) {
				text = reader.readLine();

				//Update the multiline comment state
				CheckComment();

				switch (state) {
					case State.SearchingForHeader:
						if(IsHeader()) {
							state = State.GettingArgs;
							trace("[Hix] Getting args..");
						}
						else
							ParseCommand();
					case State.GettingArgs:
						if(!isAComment && args.length == 0)
						{
							Sys.println("[Hix] Error: Unable to find any compiler args in the header!");
							state = State.FinishFail;
							break;
						}
						else if(!isAComment && args.length > 0)
						{
							trace("[Hix] Success");
							state = State.FinishSuccess;
							break;
						}
						else
						{
							//we are in a comment, lets see if there is text here
							//if there is we assume it is a command arg
							GrabArgs(text);
						}
					case State.FinishSuccess:
					case State.FinishFail:
				}
			}
		}
		catch(ex:haxe.io.Eof) {}
		reader.close();
		//Sys.println(text);

		//DO any string search/replace here
		//A special string starts with '$' and can contain any chars except for whitespace
		var sp = new EReg("^\\$([^\\s]+)", "i");
		for (i in 0...args.length) {
			if(sp.match(args[i]))
			{
				//grab the special text. Split it by the '=' sign
				//so any parameters come after the =
				var special = sp.matched(1).toLowerCase().split('=');

				//Process special commands here
				switch (special[0]) {
					case "filename":
						args[i] = fileName;
					case "datetime":
						var date = Date.now();

						//No date parameters? Ok, just do defaul Month/Day/Year
						if(special.length == 1)
							args[i] = DateTools.format(date,"%m/%e/%Y_%H:%M:%S");
						else
							args[i] = DateTools.format(date,special[1]);
				}
			}
		}
		return args;
	}

	//Grabs the compiler arguments from the given text
	//
	function GrabArgs(txt:String) 	{
		var isBlank = ~/\s*^\/*\s*$/;

		if(isBlank.match(txt)) return;

		var remhdr = new EReg("^\\s*" + HEADER_START,"i");
		var remcomm = ~/\s*\/\//;
		txt = remcomm.replace(text,"");
		txt = remhdr.replace(txt,"");
		txt = StringTools.trim(txt);

		var rgs = ParseSepString(txt, " ");
		for(a in rgs){
			args.push(a);
		}
	}

	//Looks for the start header string
	//
	function IsHeader():Bool {

		//If we are not in a comment, return
		if(!isAComment) return false;

		var header = new EReg(HEADER_START + "\\s*([^\\n]*)$","i");

		//See if there is any stuff after the header declaration
		if(header.match(text)) {
			var isBlank = ~/^\s*$/;
			if(!isBlank.match(header.matched(1))) {
				//Add this arg to our args arry and trim any whitespace
				GrabArgs(header.matched(1));
			}
			return true;
		}
		return false;
	}

	//
	//Look for any commands that occur before the header start sequence
	//
	function ParseCommand()
	{
		//If we are not in a comment, return
		if(!isAComment) return;

		var cmd = new EReg(COMMAND_PREFIX + "\\s*([^\\n]*)$","i");

		if(cmd.match(text)) {
			var cmd = cmd.matched(1).toLowerCase().split('=');
			trace('[Hix] Found command: ${cmd[0]}');

			switch(cmd[0]) {
				case "exe":
					if(cmd.length > 1 && cmd[1].length > 0) {
						exe = cmd[1];
						trace('Changing exe to: ${cmd[1]}');
					}
			}
		}
	}

	//Tells us if we are in a multi-line comment
	var inMultiLineComment:Bool = false;

	//Looks for single and multi-line comments
	//
	function CheckComment() {
		//Check for a line comment with nothing but optional spaces before it starts
		var singleComment = ~/^\s*\/\//;
		//2 different ways of instantiating an EReg
		var begin = new EReg("/\\*","i");
		var end = ~/\*\//;

		//if we weren't in a comment, see if we are now
		//Otherwise see if we are out of the comment
		if(!inMultiLineComment) {
			inMultiLineComment = begin.match(text) && !end.match(text);

			//See if we have a line comment
			isAComment = begin.match(text) || singleComment.match(text);
		}
		else {
			inMultiLineComment = !end.match(text);

			//even if the multiline comment ends, this line is still a comment
			isAComment = true;
		}

		//Sys.println('$isAComment: $text');
	}

	//
	//This parses a string separated by the given delim and deals with quoted values
	//
	static function ParseSepString(text:String, delim:String, removeQuotes:Bool = true) : Array<String> {
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
	              else if(text.charAt(endQuote + 1) == '"')  {
	              	endQuote++;
	              	endQuote = text.indexOf('"', endQuote + 1);

					while(text.charAt(endQuote + 1) == '"')
						endQuote++;
	              }

	              if(removeQuotes) {
	              	cols.push(text.substr(start + 1, endQuote - (start + 1)));
	              	//trace("[Hix] DQ: " + text.substr(start + 1, endQuote - (start + 1)));
				  }
				  else {
	              	cols.push(text.substr(start, endQuote + 1 - start));
	              	//trace("[Hix] DQ: " + text.substr(start , endQuote - start));
				  }
	              start = endQuote + 1;
	         }
	         else if(text.charAt(start) == "'") {//Single Quote value
	              var endQuote = text.indexOf("'", start + 1);

	              if(endQuote == -1)
	                   throw("[Hix] Parse Error: Expected a matching '\n" + text);

	              if(removeQuotes) {
		              cols.push(text.substr(start + 1, endQuote - (start + 1)));
		              //trace("[Hix] Q: " + text.substr(start + 1, endQuote - (start + 1)));
	          	  }
	          	  else {
		              cols.push(text.substr(start, endQuote + 1 - start));
		              //trace("[Hix] Q: " + text.substr(start, endQuote - start ));
	          	  }

	              start = endQuote + 1;
	         }
	         else if(text.charAt(start) == " " )
	         	start++;
	         else if(text.charAt(start) == delim)  {
	              start++;
	              //Check and see if it is a null value
	              while(start < end && text.charAt(start) == " ") start++;
	              if(text.charAt(start) == delim)
	              {
	              	//An empty column
	              	//cols.push("");
	              }
	         }
	         else {
	              var lastChar = text.indexOf(delim, start);
	              if(lastChar == -1)
	                   lastChar = end;
	              if(lastChar - start > 0)  {
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

Then compile by running:
hix <inputFile.hx>

No more hxml build files needed!

Special arguments:
$filename -> inserts the name of the current file into the args list
$datetime<=optional strftime format specification> ->Note not all strftime settings are supported
$datetime -> without specifying a strftime format will output: %m/%e/%Y_%H:%M:%S

You can also change the program that is executed with the args (by default it is haxe)
by placing a special command BEFORE the start header:
::exe=<name of executable>

=============================================================================
			";
            inst = StringTools.replace(inst,"$HEADER_START", HEADER_START );
            Sys.print(inst);
	}
}