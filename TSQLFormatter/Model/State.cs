﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace TSQLFormatter.Model
{
    public enum State
    {
        General,
        KeywordFunctionOther,
        Comment,
        String,
        EndUnknownLexem,
        End
    }
}
