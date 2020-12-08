//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setup_env::::else:://::end::
//::hix       -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -D analyzer -cpp bin -lib heaps --no-traces -dce full
//::hix:hl    -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -D analyzer -hl ${filenameNoExt}.hl -lib heaps -lib hlsdl --no-traces -dce full
//::hix:js   -main ${filenameNoExt} ::if (SrcDir != null)::-cp ::SrcDir::::else::::end:: -lib heaps -js ${filenameNoExt}.js -debug 
//
class ::class_name:: extends hxd.App {
    override function init() {
        var tf = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
        tf.text = "Hello World !";
    }
    static function main() {
        new ::class_name::();
    }
}
