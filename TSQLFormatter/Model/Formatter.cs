using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Model
{
    public class Formatter
    {
        public string GetFormattedText(string unformattedText)
        {
            var syntaxAnalyzer = new SyntaxAnalyzer();
            var lexems = syntaxAnalyzer.Parse(unformattedText);
            var keywordLexems = lexems.Where(x => x.Kind == LexemKind.Keyword || x.Kind == LexemKind.Function);
            var unformattedTextArray = unformattedText.ToCharArray();
            SetUpperCase(unformattedTextArray, keywordLexems);
            var formattedText = new string(unformattedTextArray);

            return formattedText;
        }

        public void SetUpperCase(char[] unformattedTextArray, IEnumerable<Lexem> keywordLexems)
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
