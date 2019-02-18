using Microsoft.VisualStudio.TestTools.UnitTesting;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using TSQLFormatter.Model;

namespace TSQLFormatter.Test.Model
{
    [TestClass]
    public class SyntaxAnalyzerTest
    {
        private SyntaxAnalyzer _syntaxAnalyzer;

        [TestInitialize]
        public void Init()
        {
            _syntaxAnalyzer = new SyntaxAnalyzer();
        }

        [TestMethod]
        public void Parse_Query()
        {
            var text = "select * from MyTable";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(4, lexems.Count);
            int i = 0;
            Assert.AreEqual(0, lexems[i].StartPosition);
            Assert.AreEqual(5, lexems[i].EndPosition);
            Assert.AreEqual("select", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(7, lexems[i].StartPosition);
            Assert.AreEqual(7, lexems[i].EndPosition);
            Assert.AreEqual("*", lexems[i].Name);
            Assert.AreEqual(LexemKind.Delimiter, lexems[i].Kind);
            i++;
            Assert.AreEqual(9, lexems[i].StartPosition);
            Assert.AreEqual(12, lexems[i].EndPosition);
            Assert.AreEqual("from", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(14, lexems[i].StartPosition);
            Assert.AreEqual(20, lexems[i].EndPosition);
            Assert.AreEqual("MyTable", lexems[i].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[i].Kind);
        }

        [TestMethod]
        public void Parse_QueryTempTable()
        {
            var text = "select * from #TempTable";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(4, lexems.Count);
            Assert.AreEqual("#TempTable", lexems[3].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[3].Kind);
        }

        [TestMethod]
        public void Parse_QueryWithWhere()
        {
            var text = "select * from MyTable where a > 1";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(8, lexems.Count);
            int i = 0;
            Assert.AreEqual(0, lexems[i].StartPosition);
            Assert.AreEqual(5, lexems[i].EndPosition);
            Assert.AreEqual("select", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(7, lexems[i].StartPosition);
            Assert.AreEqual(7, lexems[i].EndPosition);
            Assert.AreEqual("*", lexems[i].Name);
            Assert.AreEqual(LexemKind.Delimiter, lexems[i].Kind);
            i++;
            Assert.AreEqual(9, lexems[i].StartPosition);
            Assert.AreEqual(12, lexems[i].EndPosition);
            Assert.AreEqual("from", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(14, lexems[i].StartPosition);
            Assert.AreEqual(20, lexems[i].EndPosition);
            Assert.AreEqual("MyTable", lexems[i].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[i].Kind);
            i++;
            Assert.AreEqual(22, lexems[i].StartPosition);
            Assert.AreEqual(26, lexems[i].EndPosition);
            Assert.AreEqual("where", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(28, lexems[i].StartPosition);
            Assert.AreEqual(28, lexems[i].EndPosition);
            Assert.AreEqual("a", lexems[i].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[i].Kind);
            i++;
            Assert.AreEqual(30, lexems[i].StartPosition);
            Assert.AreEqual(30, lexems[i].EndPosition);
            Assert.AreEqual(">", lexems[i].Name);
            Assert.AreEqual(LexemKind.Delimiter, lexems[i].Kind);
            i++;
            Assert.AreEqual(32, lexems[i].StartPosition);
            Assert.AreEqual(32, lexems[i].EndPosition);
            Assert.AreEqual("1", lexems[i].Name);
            Assert.AreEqual(LexemKind.Other, lexems[i].Kind);
        }

        [TestMethod]
        public void Parse_Unescape()
        {
            var text = "select [group] from MyTable";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(4, lexems.Count);
            Assert.AreEqual(7, lexems[1].StartPosition);
            Assert.AreEqual(13, lexems[1].EndPosition);
            Assert.AreEqual("[group]", lexems[1].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[1].Kind);
        }

        [TestMethod]
        public void Parse_Unescape2()
        {
            var text = "select [group]from MyTable";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();

            Assert.AreEqual(4, lexems.Count);

            Assert.AreEqual(7, lexems[1].StartPosition);
            Assert.AreEqual(13, lexems[1].EndPosition);
            Assert.AreEqual("[group]", lexems[1].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[1].Kind);

            Assert.AreEqual(14, lexems[2].StartPosition);
            Assert.AreEqual(17, lexems[2].EndPosition);
            Assert.AreEqual("from", lexems[2].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[2].Kind);
        }

        [TestMethod]
        public void Parse_UnescapeWithDelimiter()
        {
            var text = "select [group-1] from MyTable";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(4, lexems.Count);
            Assert.AreEqual("[group-1]", lexems[1].Name);
            Assert.AreEqual(LexemKind.Identifier, lexems[1].Kind);
        }

        [TestMethod]
        public void Parse_Comments()
        {
            var text = "select * from MyTable -- comments";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(5, lexems.Count);
            Assert.AreEqual(22, lexems[4].StartPosition);
            Assert.AreEqual(32, lexems[4].EndPosition);
            Assert.AreEqual("-- comments", lexems[4].Name);
            Assert.AreEqual(LexemKind.Comment, lexems[4].Kind);
        }

        [TestMethod]
        public void Parse_Strings()
        {
            var text = "'select [group] from MyTable'";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(1, lexems.Count);
            Assert.AreEqual(0, lexems[0].StartPosition);
            Assert.AreEqual(28, lexems[0].EndPosition);
            Assert.AreEqual("'select [group] from MyTable'", lexems[0].Name);
            Assert.AreEqual(LexemKind.String, lexems[0].Kind);
        }

        [TestMethod]
        public void Parse_StringsMultiline()
        {
            var text = @"'select [group]
from MyTable'";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(1, lexems.Count);
            Assert.AreEqual(0, lexems[0].StartPosition);
            Assert.AreEqual(29, lexems[0].EndPosition);
            Assert.AreEqual(@"'select [group]
from MyTable'", lexems[0].Name);
            Assert.AreEqual(LexemKind.String, lexems[0].Kind);
        }

        [TestMethod]
        public void Parse_Variables()
        {
            var text = "declare @var int";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(3, lexems.Count);
            Assert.AreEqual("declare", lexems[0].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[0].Kind);
            Assert.AreEqual("@var", lexems[1].Name);
            Assert.AreEqual(LexemKind.Variable, lexems[1].Kind);
            Assert.AreEqual("int", lexems[2].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[2].Kind);
        }

        [TestMethod]
        public void Parse_N()
        {
            var text = "N'string'";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(2, lexems.Count);
            Assert.AreEqual("N", lexems[0].Name);
            Assert.AreEqual(LexemKind.Other, lexems[0].Kind);
            Assert.AreEqual("'string'", lexems[1].Name);
            Assert.AreEqual(LexemKind.String, lexems[1].Kind);
        }

        [TestMethod]
        public void Parse_StoredProcedure()
        {
            var text = "exec sp_someprocedure";
            var lexems = _syntaxAnalyzer.Parse(text).ToList();
            Assert.AreEqual(2, lexems.Count);
            Assert.AreEqual("exec", lexems[0].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[0].Kind);
            Assert.AreEqual("sp_someprocedure", lexems[1].Name);
            Assert.AreEqual(LexemKind.StoredProcedure, lexems[1].Kind);
        }

        [TestMethod]
        public void Parse_SQLFile_1()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\1.sql");
            var lexems = _syntaxAnalyzer.Parse(fileText).ToList();
            Assert.AreEqual(637, lexems.Count);
            lexems.ForEach(x => Assert.IsTrue(x.StartPosition <= fileText.Length));
            lexems.ForEach(x => Assert.IsTrue(x.EndPosition <= fileText.Length));
        }

        [TestMethod]
        public void Parse_SQLFile_2()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\2.sql");
            var lexems = _syntaxAnalyzer.Parse(fileText).ToList();
            Assert.AreEqual(1744, lexems.Count);
            lexems.ForEach(x => Assert.IsTrue(x.StartPosition <= fileText.Length));
            lexems.ForEach(x => Assert.IsTrue(x.EndPosition <= fileText.Length));
        }

        [TestMethod]
        public void Parse_SQLFile_3()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\3.sql");
            var lexems = _syntaxAnalyzer.Parse(fileText).ToList();
            Assert.AreEqual(31058, lexems.Count);
            lexems.ForEach(x => Assert.IsTrue(x.StartPosition <= fileText.Length));
            lexems.ForEach(x => Assert.IsTrue(x.EndPosition <= fileText.Length));
        }
    }
}
