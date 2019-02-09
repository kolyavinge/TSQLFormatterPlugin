using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Model
{
    public class Lexem
    {
        public string Name { get; set; }

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
        Delimiter,
        Other
    }
}
