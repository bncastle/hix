package lib;

import sys.io.File;
import sys.FileSystem;

class EmbeddedFile {
    public var contents(default, null):StringBuf;
    public var name(default, null):String;
    public var tmpFile(default, null):Bool;

    public function new(name:String, isTmp:Bool){
        contents = new StringBuf();
        this.name = name;
        tmpFile =isTmp;
    }

    public function Exists(): Bool{
        return FileSystem.exists(name);
    }

    public function Generate():Bool{
        if(Exists()){
            return false;
        }
        else{
            trace('[Hix] creating embedded file: ${name}');
            File.saveContent(name, contents.toString());
            return true;
        }
    }

    public function Delete(): Bool{
        if(FileSystem.exists(name)){
            FileSystem.deleteFile(name);
            return true;
        }
        return false;
    }
}