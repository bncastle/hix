package lib;

import haxe.macro.Context;
import haxe.macro.Expr;
import sys.io.File;
import haxe.io.Path;
using Lambda;


class Macros{
    macro static public function GetTemplateFileNames(){
        var files = Util.GetFilesWithExt("file_templates",null);
        var exprs = [for(file in files) macro {key: $v{file}, val: $v{File.getContent(Path.join(["file_templates", file]))}}];
        return macro $a{exprs};
    }
}