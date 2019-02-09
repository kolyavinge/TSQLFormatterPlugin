using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Model
{
    public class SyntaxAnalyzer
    {
        private HashSet<char> _delimiters = new HashSet<char>(
            new[] { ' ', ',', '.', ';', '(', ')', '+', '-', '*', '/', '<', '>', '=', '[', ']' });

        private HashSet<string> _keywords;
        private HashSet<string> _functions;

        public SyntaxAnalyzer()
        {
            _keywords = new HashSet<string>(new KeywordsCollection().ToList());
            _functions = new HashSet<string>(new FunctionsCollection().ToList());
        }

        public IEnumerable<Lexem> Parse(string text)
        {
            if (String.IsNullOrWhiteSpace(text)) yield break;
            var lexemNameArray = new char[256];
            int lexemNameArrayIndex = 0;
            int pos = 0;
            char ch;
            Lexem lexem = null;
            switch (1)
            {
                case 1:
                    if (pos >= text.Length) break;
                    ch = text[pos];
                    if (IsSpaceOrReturn(ch))
                    {
                        pos++;
                        goto case 1;
                    }
                    else if (IsDelimiter(ch))
                    {
                        lexem = new Lexem { StartPosition = pos, EndPosition = pos, Kind = LexemKind.Delimiter, Name = ch.ToString() };
                        yield return lexem;
                        pos++;
                        goto case 1;
                    }
                    else
                    {
                        lexem = new Lexem { StartPosition = pos };
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case 2;
                    }
                case 2:
                    if (pos >= text.Length)
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        lexem.Kind = GetLexemKind(lexem.Name);
                        yield return lexem;
                        break;
                    }
                    ch = text[pos];
                    if (IsSpaceOrReturn(ch) || IsDelimiter(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        lexem.Kind = GetLexemKind(lexem.Name);
                        yield return lexem;
                        lexemNameArrayIndex = 0;
                        goto case 1;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case 2;
                    }
            }
        }

        private LexemKind GetLexemKind(string lexemName)
        {
            return IsKeyword(lexemName) ? LexemKind.Keyword : (IsFunction(lexemName) ? LexemKind.Function : LexemKind.Other);
        }

        private bool IsKeyword(string lexemName)
        {
            return _keywords.Contains(lexemName, StringComparer.InvariantCultureIgnoreCase);
        }

        private bool IsFunction(string lexemName)
        {
            return _functions.Contains(lexemName, StringComparer.InvariantCultureIgnoreCase);
        }

        private bool IsDelimiter(char ch)
        {
            return _delimiters.Contains(ch);
        }

        private bool IsSpaceOrReturn(char ch)
        {
            return ch == ' ' || ch == '\r' || ch == '\n';
        }
    }
}
