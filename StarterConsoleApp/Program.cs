using System.IO;
using TSQLFormatter.Model;

namespace StarterConsoleApp
{
    class Program
    {
        static void Main(string[] args)
        {
            var fileText = File.ReadAllText("..\\..\\..\\TSQLFormatter.Test\\SQLFiles\\1.sql");
            var formatter = new Formatter();
            for (int i = 0; i < 10000; i++)
            {
                var result = formatter.GetFormattedText(fileText);
            }
        }
    }
}
