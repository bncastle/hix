//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setupEnv::::else:://::end::
//::hix       -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -D analyzer -cpp bin -lib heaps --no-traces -dce full
//::hix:debug -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -cpp bin -lib heaps 
//::hix:js   -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -lib heaps -js ${filenameNoExt}.js -debug 
//::hix:run   -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: --interp -lib heaps 
//
class ::ClassName:: extends hxd.App {
    override function init() {
        var tf = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
        tf.text = "Hello World !";
    }
    static function main() {
        new ::ClassName::();
    }
}
