using System;
using System.Collections.Generic;
using System.Linq;

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
            var result = new List<Lexem>();
            if (String.IsNullOrWhiteSpace(text)) return result;
            var lexemNameArray = new char[10 * 1024];
            int lexemNameArrayIndex = 0;
            int pos = 0;
            char ch;
            Lexem lexem = null;
            switch (State.General)
            {
                case State.General:
                    if (pos >= text.Length) break;
                    ch = text[pos];
                    if (IsSpace(ch) || IsReturn(ch))
                    {
                        pos++;
                        goto case State.General;
                    }
                    else if (ch == '-' && pos + 1 < text.Length && text[pos + 1] == '-') // comment start
                    {
                        lexemNameArray[lexemNameArrayIndex++] = '-';
                        lexemNameArray[lexemNameArrayIndex++] = '-';
                        lexem = new Lexem { StartPosition = pos, Kind = LexemKind.Comment };
                        pos += 2;
                        goto case State.Comment;
                    }
                    else if (ch == '\'') // string start
                    {
                        if (result.Any() && result.Last().Name == "N")
                        {
                            result.Last().Kind = LexemKind.Other;
                        }
                        lexem = new Lexem { StartPosition = pos, Kind = LexemKind.String };
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.String;
                    }
                    else if (ch == '[')
                    {
                        lexemNameArray[lexemNameArrayIndex++] = '[';
                        lexem = new Lexem { StartPosition = pos, Kind = LexemKind.Identifier };
                        pos++;
                        goto case State.Identifier;
                    }
                    else if (IsDelimiter(ch))
                    {
                        lexem = new Lexem { StartPosition = pos, EndPosition = pos, Kind = LexemKind.Delimiter, Name = ch.ToString() };
                        result.Add(lexem);
                        pos++;
                        goto case State.General;
                    }
                    else
                    {
                        lexem = new Lexem { StartPosition = pos };
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.KeywordFunctionOther;
                    }
                case State.KeywordFunctionOther: // keyword, function or other name
                    if (pos >= text.Length) goto case State.EndUnknownLexem;
                    ch = text[pos];
                    if (IsSpace(ch) || IsReturn(ch) || IsDelimiter(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        lexem.Kind = GetLexemKind(lexem.Name);
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        goto case State.General;
                    }
                    else if (ch == '\'' && lexemNameArray[lexemNameArrayIndex - 1] == 'N')
                    {
                        lexem.EndPosition = pos;
                        lexem.Name = "N";
                        lexem.Kind = LexemKind.Other;
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        goto case State.General;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.KeywordFunctionOther;
                    }
                case State.Comment: // comment
                    if (pos >= text.Length) goto case State.End;
                    ch = text[pos];
                    if (IsReturn(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        pos++;
                        goto case State.General;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.Comment;
                    }
                case State.String: // string
                    if (pos >= text.Length) goto case State.End;
                    ch = text[pos];
                    if (ch == '\'')
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        lexem.EndPosition = pos;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        pos++;
                        goto case State.General;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.String;
                    }
                case State.Identifier:
                    if (pos >= text.Length) goto case State.End;
                    ch = text[pos];
                    if (IsReturn(ch))
                    {
                        lexem.EndPosition = pos - 1;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        pos++;
                        goto case State.General;
                    }
                    else if (ch == ']')
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        lexem.EndPosition = pos;
                        lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                        result.Add(lexem);
                        lexemNameArrayIndex = 0;
                        pos++;
                        goto case State.General;
                    }
                    else
                    {
                        lexemNameArray[lexemNameArrayIndex++] = ch;
                        pos++;
                        goto case State.Identifier;
                    }
                case State.EndUnknownLexem:
                    lexem.EndPosition = pos - 1;
                    lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                    lexem.Kind = GetLexemKind(lexem.Name);
                    result.Add(lexem);
                    break;
                case State.End:
                    lexem.EndPosition = pos - 1;
                    lexem.Name = new string(lexemNameArray, 0, lexemNameArrayIndex);
                    result.Add(lexem);
                    break;
            }

            return result;
        }

        private LexemKind GetLexemKind(string lexemName)
        {
            if (IsKeyword(lexemName)) return LexemKind.Keyword;
            if (IsFunction(lexemName)) return LexemKind.Function;
            if (IsVariable(lexemName)) return LexemKind.Variable;
            if (IsIdentifier(lexemName)) return LexemKind.Identifier;

            return LexemKind.Other;
        }

        private bool IsKeyword(string lexemName)
        {
            return _keywords.Contains(lexemName, StringComparer.InvariantCultureIgnoreCase);
        }

        private bool IsFunction(string lexemName)
        {
            return _functions.Contains(lexemName, StringComparer.InvariantCultureIgnoreCase);
        }

        private bool IsVariable(string lexemName)
        {
            return lexemName.StartsWith("@");
        }

        private bool IsIdentifier(string lexemName)
        {
            return Char.IsLetter(lexemName[0]) || lexemName[0] == '_' || lexemName[0] == '#';
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
