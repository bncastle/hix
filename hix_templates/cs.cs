
//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setupEnv::::else:://::end::
//::hix -optimize -out:${filenameNoExt}.exe ${filename}
//::hix:debug -define:DEBUG -out:${filenameNoExt}.exe ${filename}
//

public class ::ClassName::
{
    static void Main(string[] args)
    {

    }
}