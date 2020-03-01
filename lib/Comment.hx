package lib;

class Comment{
    var singleLine: EReg; 
    var multiStart: EReg; 
    var multiEnd: EReg; 
    public function new(single:EReg, multiStart:EReg, multiEnd: EReg){
        singleLine = single;
        this.multiStart = multiStart;
        this.multiEnd = multiEnd;
    }

    public function IsSingle(text:String):Bool{ return text != null && singleLine.match(text);}
    public function IsMultiStart(text:String):Bool{ return text != null && multiStart.match(text);}
    public function IsMultiEnd(text:String):Bool{ return text != null && multiEnd.match(text);}
}