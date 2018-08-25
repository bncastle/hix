using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
using System.Reflection;
using System.Xml;
using System.Text.RegularExpressions;

//This program can be used with my Hix.exe utility
//Note: before using hix on this file, be sure to set the Visual Studio command line environment
//
//::hix -out:${filenameNoExt}.exe -optimize ${filename}
//
namespace AddCopyrightHeader
{
    class CopyrightHeader
    {
        static void Main(string[] args)
        {
            string dir = string.Empty;
            CopyrightHeader copyrightHeader = new CopyrightHeader();

            //No arguments? then run the program with the target being this program's
            //containing directory
            if (args.Length == 0)
            {
                Assembly exe = typeof(CopyrightHeader).Assembly;
                dir = Path.GetDirectoryName(exe.Location);
            }
            else
            {
                if (!Directory.Exists(args[0]))
                {
                    Console.WriteLine("The directory [{0}] does not exist!", args[0]);
                    return;
                }

                dir = args[0];
            }

            Console.WriteLine("Getting files from: {0}", dir);

            string[] files = Directory.GetFiles(dir, "*.cs", SearchOption.AllDirectories);

            //Now filter the files
            string[] filteredFiles = copyrightHeader.FilterFiles(files);

            foreach (string s in filteredFiles)
            {
                copyrightHeader.AddHeader(s);
            }
        }

        Regex _blank, _comment;
        public CopyrightHeader()
        {
            _blank = new Regex(@"^\s*$", RegexOptions.Singleline);
            _comment = new Regex(@"^\s*(?://|/\*)", RegexOptions.Singleline);
            GetHeader();
        }

        public string[] FilterFiles(string[] files)
        {
            List<string> filteredList = new List<string>();

            foreach (string s in files)
            {
                //Skip the generated AssemblyInfo files
                if (Path.GetFileName(s) == "AssemblyInfo.cs")
                {
                    Console.WriteLine("{0} is a pre-generated file...skipping it", s);
                    continue;
                }

                filteredList.Add(s);
            }

            return filteredList.ToArray();
        }

        string _header;
        void GetHeader()
        {
            string headerFile = "Header.xml";

            //Pre-Header
            _header = "#region File Description\r\n";

            //Check and make sure the header file exists
            if (!File.Exists(headerFile))
                throw new Exception(string.Format("The header file: {0} could not be found!", headerFile));

            XmlTextReader xr = new XmlTextReader(new FileStream(headerFile, FileMode.Open, FileAccess.Read));
            while (xr.NodeType != XmlNodeType.CDATA)
                xr.Read();

            _header += xr.Value;
            xr.Close();

            //post-header
            _header += "#endregion\r\n\r\n";

            //TOOD: perform any string replacement/manipulation on the header here
            Regex date = new Regex(@"{Date}", RegexOptions.Multiline);
            Regex year = new Regex(@"{Year}", RegexOptions.Multiline);

            _header = date.Replace(_header, DateTime.Now.ToShortDateString());
            _header = year.Replace(_header, DateTime.Now.Year.ToString());
        }

        public void AddHeader(string file)
        {
            StreamReader sr = null;
            string text;
            bool headerAdded = false;

            StringBuilder sb = new StringBuilder();

            try
            {
                sr = new StreamReader(file);

                while ((text = sr.ReadLine()) != null)
                {
                    if (!_blank.IsMatch(text) && !headerAdded)
                    {
                        //is it a region
                        //If so then we won't insert our header
                        //Headers must go in a region
                        if (_comment.IsMatch(text))
                        {
                            Console.WriteLine("{0} looks to already have a header", file);
                            return;
                        }
                        else
                        {
                            Console.WriteLine("Adding header to {0}", file);
                            sb.Append(_header);
                            headerAdded = true;
                        }
                    }

                    //Copy file contents to the string
                    sb.Append(text + "\r\n");
                }

            }
            finally
            {
                if (sr != null)
                    sr.Close();
            }


            //backup the original file and replace it with the contents of the memory stream
            string bak = Path.GetDirectoryName(file) + "\\" + Path.GetFileNameWithoutExtension(file) + ".bak";
            File.Move(file, bak);

            StreamWriter wr = new StreamWriter(file);
            wr.Write(sb.ToString());
            wr.Close();
        }
    }
}

//This is the manifest file that allows us to request to be run as admin
//it is embedded and will be automatically extracted when using hix.exe
//
/*::genfile=Header.xml
<header>
<![CDATA[//
// Written by Bryan Castleberry
// Copyright (c) {Year} Bryan Castleberry
//
// Date: {Date}
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.
//
]]>>
</header>
*/