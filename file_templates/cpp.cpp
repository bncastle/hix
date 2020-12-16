//This program can be compiled with the Hix.exe utility
::if (author != null):://Author: ::author::::else:://::end::
::if (setupEnv != null):://::SetupKey:: ::setup_env::::else:://::end::
//::incDirs=
//::libDirs=
//::libs=
//::defines=_CRT_SECURE_NO_WARNINGS 
//::hix

#include <cstdio>

/**
 * @brief Entry-point of the application, showing how to play with precise time ticks.
 */
int main()
{
    printf("Hello World!");
    return 0;
}