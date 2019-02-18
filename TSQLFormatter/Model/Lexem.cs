using System;

namespace TSQLFormatter.Model
{
    public class Lexem
    {
        public string Name { get; set; }

        public bool IsUnescaped
        {
            get { return Name[0] == '[' && Name[Name.Length - 1] == ']'; }
        }

        public LexemKind Kind { get; set; }

        public int StartPosition { get; set; }

        public int EndPosition { get; set; }

        public override string ToString()
        {
            return String.Format("{0} {1} [{2}:{3}]", Name, Kind, StartPosition, EndPosition);
        }
    }

    public enum LexemKind
    {
        Keyword,
        Function,
        StoredProcedure,
        Identifier,
        Variable,
        String,
        Comment,
        Delimiter,
        Other,
    }
}
