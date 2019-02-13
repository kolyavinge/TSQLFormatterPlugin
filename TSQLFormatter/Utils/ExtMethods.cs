using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Utils
{
    public static class StringExt
    {
        public static string[] SplitNewLine(this string str)
        {
            return str.Split(new string[] { Environment.NewLine }, StringSplitOptions.None);
        }
    }

    public static class EnumerableExt
    {
        public static string JoinToString(this IEnumerable<string> collection, string separator)
        {
            return String.Join(separator, collection);
        }
    }
}
