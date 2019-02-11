using System.IO;
using TSQLFormatter.Model;

namespace StarterConsoleApp
{
    class Program
    {
        static void Main(string[] args)
        {
            var fileText = File.ReadAllText("..\\..\\..\\TSQLFormatter.Test\\SQLFiles\\3.sql");
            var formatter = new Formatter();
            for (int i = 0; i < 1; i++)
            {
                var result = formatter.GetFormattedText(fileText);
            }
        }
    }
}
