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
            new[] { ' ', ',', '.', ';', '(', ')', '+', '-', '*', '/', '<', '>', '=' });

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
                    if (IsSpace(ch) || IsReturn(ch))
                    {
                        pos++;
                        goto case 1;
                    }
                    else if (ch == '-' && pos + 1 < text.Length && text[pos + 1] == '-')
                    {
                        lexemNameArray[lexemNameArrayIndex++] = '-';
                        lexemNameArray[lexemNameArrayIndex++] = '-';
                        lexem = new Lexem { StartPosition = pos, Kind = LexemKind.Comments };
                        pos += 2;
                        goto case 3;
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
                    if (IsSpace(ch) || IsReturn(ch) || IsDelimiter(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        lexem.Kind = GetLexemKind(lexem.Name);
                        yield return lexem;
                        lexemNameArrayIndex = 0;
                        goto case 1;
                    }
                    else if (ch == ']')
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        lexem.EndPosition = pos;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        lexem.Kind = LexemKind.Other;
                        yield return lexem;
                        lexemNameArrayIndex = 0;
                        pos++;
                        goto case 1;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case 2;
                    }
                case 3:
                    if (pos >= text.Length)
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        yield return lexem;
                        break;
                    }
                    ch = text[pos];
                    if (IsReturn(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        yield return lexem;
                        pos++;
                        goto case 1;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case 3;
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

        private bool IsSpace(char ch)
        {
            return ch == ' ' || ch == '\t';
        }

        private bool IsReturn(char ch)
        {
            return ch == '\r' || ch == '\n';
        }
    }
}
