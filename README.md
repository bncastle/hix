# Hix

## Introduction

Hix removes the need for build.hxml files or command line arguments to the haxe compiler.
Instead, the compilation flags are stored in the source code where the main class is located
using special headers stored in comments near the top of the file.

## Building

To build, open a command prompt to the Hix directory and type:

*`haxe.exe build.hxml`*

## How to Use

Ex: To build Main.hx as a cpp target, simply add the following in a comment near the top of the Main.hx file:

```
//hix:: -main Main --no-traces -dce full -cpp bin
```

The `hix::` text fragment above tells Hix to expect build arguments and to start parsing them. Any build config
args must begin with this. The above comment residing in Main.hx then enables that build configuration to begin
executed by typing: *`hix Main.hx`*

Hix also understands multi-line build arguments so the following is also valid:

```
//hix::
-main Main
--no-traces
-dce full
-cpp bin
```

Hix also supports multiple different build configs which makes it easy to build for different targets:
```
//hix:: -main Main --no-traces -dce full -cpp bin
//::hix:label1 -main HR --no-traces -dce full -neko hr.n
//::hix:moon -main HR -lua main.lua
```

With the above chunk of comments in place, the cpp target is the DEFAULT and can be built as before
by executing: *`hix Main.hx`* on the command line. Note that the other two lines are a bit different.
They have labels. Note the 'label1' and 'moon' text in each of the lines. These labels can be any text
desired and now allow us to change build targets by simply adding the label at the end. Building the
neko target is simply a matter of typing: *`hix Main.hx label1`* and your build begins! Any valid argument
the Haxe compiler is supported. To get a list of them, just execute Haxe at the command line with no arguments.

## Special parameters

Hix also supports some special parameters that can be used as arguments to some of the Haxe command lines switches.
Note that all of these special parameters have the *`$`* prefix.

*`$filename`* inserts the name of the current file.

*`$datetime`* outputs the current date in the following format: %m/%e/%Y_%H:%M:%S

*`$datetime=(formatString)`*  outputs the current date using the given strftime format specification. 
(Not all strftime settings are supported.)

When Hix is executed, it normally runs `Haxe.exe`, but this can be changed by placing the following
special command BEFORE any `hix::` headers:
```
//::exe=app.exe
```
With the above command placed before any `hix::` headers, Hix will no longer execute the given build arguments
using the default `Haxe.exe`, but will instead use `app.exe`