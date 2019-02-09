﻿using System.Collections;
using System.Collections.Generic;

namespace TSQLFormatter.Model
{
    public class FunctionsCollection : IEnumerable<string>
    {
        private List<string> _functions = new List<string>
        {
            "ASCII",
            "CHAR",
            "CHARINDEX",
            "CONCAT",
            "Concat",
            "CONCAT_WS",
            "DATALENGTH",
            "DIFFERENCE",
            "FORMAT",
            "LEFT",
            "LEN",
            "LOWER",
            "LTRIM",
            "NCHAR",
            "PATINDEX",
            "QUOTENAME",
            "REPLACE",
            "REPLICATE",
            "REVERSE",
            "RIGHT",
            "RTRIM",
            "SOUNDEX",
            "SPACE",
            "STR",
            "STUFF",
            "SUBSTRING",
            "TRANSLATE",
            "TRIM",
            "UNICODE",
            "UPPER",
            "ABS",
            "ACOS",
            "ASIN",
            "ATAN",
            "ATN2",
            "AVG",
            "CEILING",
            "COUNT",
            "COS",
            "COT",
            "DEGREES",
            "EXP",
            "FLOOR",
            "LOG",
            "LOG10",
            "MAX",
            "MIN",
            "PI",
            "POWER",
            "RADIANS",
            "RAND",
            "ROUND",
            "SIGN",
            "SIN",
            "SQRT",
            "SQUARE",
            "SUM",
            "TAN",
            "CURRENT_TIMESTAMP",
            "DATEADD",
            "DATEDIFF",
            "DATEFROMPARTS",
            "DATENAME",
            "DATEPART",
            "DAY",
            "GETDATE",
            "GETUTCDATE",
            "ISDATE",
            "MONTH",
            "SYSDATETIME",
            "YEAR",
            "CAST",
            "COALESCE",
            "CONVERT",
            "CURRENT_USER",
            "ISNULL",
            "ISNUMERIC",
            "NULLIF",
            "SESSION_USER",
            "SESSIONPROPERTY",
            "SYSTEM_USER",
            "USER_NAME",
            "OBJECT_ID",
            "APPROX_COUNT_DISTINCT",
            "STDEV",
            "CHECKSUM_AGG",
            "STDEVP",
            "STRING_AGG",
            "COUNT_BIG",
            "GROUPING",
            "GROUPING_ID",
            "VAR",
            "VARP"
        };

        public IEnumerator<string> GetEnumerator()
        {
            return _functions.GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return _functions.GetEnumerator();
        }
    }
}
