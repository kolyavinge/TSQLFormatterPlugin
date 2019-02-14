using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using TSQLFormatter.Utils;

namespace TSQLFormatter.Model
{
    public class Formatter
    {
        public string GetFormattedText(string unformattedText)
        {
            var syntaxAnalyzer = new SyntaxAnalyzer();
            var lexems = syntaxAnalyzer.Parse(unformattedText);
            var keywordLexems = lexems.Where(x => x.Kind == LexemKind.Keyword || x.Kind == LexemKind.Function);
            var identifiersLexems = lexems.Where(x => x.Kind == LexemKind.Identifier);
            var upperCaseKeywordsText = ToUpperCaseKeywords(unformattedText, keywordLexems);
            var unescaped = Unescape(upperCaseKeywordsText, identifiersLexems);
            var trimmedText = RemoveTailSpaces(unescaped);
            var tabToSpaces = trimmedText.Replace("\t", "    ");

            return tabToSpaces;
        }

        private string ToUpperCaseKeywords(string inputText, IEnumerable<Lexem> keywordLexems)
        {
            var inputTextArray = inputText.ToCharArray();
            foreach (var keywordLexem in keywordLexems)
            {
                for (int i = keywordLexem.StartPosition; i <= keywordLexem.EndPosition; i++)
                {
                    inputTextArray[i] = Char.ToUpper(inputTextArray[i]);
                }
            }

            return new string(inputTextArray);
        }

        private string RemoveTailSpaces(string inputText)
        {
            return inputText.SplitNewLine().Select(x => x.TrimEnd()).JoinToString(Environment.NewLine);
        }

        private string Unescape(string inputText, IEnumerable<Lexem> identifiersLexems)
        {
            var inputTextStringBuilder = new StringBuilder(inputText);
            var identifiersLexemsArray = identifiersLexems.Where(x => !x.IsUnescaped).OrderBy(x => x.StartPosition).ToArray();
            for (int i = 0; i < identifiersLexemsArray.Length; i++)
            {
                var identifierLexem = identifiersLexemsArray[i];
                inputTextStringBuilder.Insert(identifierLexem.StartPosition + 2 * i, '[');
                inputTextStringBuilder.Insert(identifierLexem.EndPosition + 2 * i + 2, ']');
            }

            return inputTextStringBuilder.ToString();
        }
    }
}
