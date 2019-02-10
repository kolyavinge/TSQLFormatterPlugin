using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Model
{
    public class Formatter
    {
        public string GetFormattedText(string unformattedText)
        {
            var keywordLexems = GetKeywords(unformattedText);
            var unformattedTextArray = unformattedText.ToCharArray();
            SetUpperCase(unformattedTextArray, keywordLexems);
            var trimmedText = RemoveTailSpaces(unformattedTextArray);

            return trimmedText;
        }

        private string RemoveTailSpaces(char[] unformattedTextArray)
        {
            var result = new StringBuilder();
            using (var stream = new StreamReader(new MemoryStream(Encoding.UTF8.GetBytes(unformattedTextArray))))
            {
                string line = null;
                while ((line = stream.ReadLine()) != null)
                {
                    result.AppendLine(line.TrimEnd());
                }
            }

            return result.ToString();
        }

        private IEnumerable<Lexem> GetKeywords(string unformattedText)
        {
            var syntaxAnalyzer = new SyntaxAnalyzer();
            var lexems = syntaxAnalyzer.Parse(unformattedText);
            var keywordLexems = lexems.Where(x => x.Kind == LexemKind.Keyword || x.Kind == LexemKind.Function);

            return keywordLexems;
        }

        private void SetUpperCase(char[] unformattedTextArray, IEnumerable<Lexem> keywordLexems)
        {
            foreach (var keywordLexem in keywordLexems)
            {
                for (int i = keywordLexem.StartPosition; i <= keywordLexem.EndPosition; i++)
                {
                    unformattedTextArray[i] = Char.ToUpper(unformattedTextArray[i]);
                }
            }
        }
    }
}
