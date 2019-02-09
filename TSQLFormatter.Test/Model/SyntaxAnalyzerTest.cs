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
            Assert.AreEqual(LexemKind.Other, lexems[i].Kind);
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
            Assert.AreEqual(LexemKind.Other, lexems[i].Kind);
            i++;
            Assert.AreEqual(22, lexems[i].StartPosition);
            Assert.AreEqual(26, lexems[i].EndPosition);
            Assert.AreEqual("where", lexems[i].Name);
            Assert.AreEqual(LexemKind.Keyword, lexems[i].Kind);
            i++;
            Assert.AreEqual(28, lexems[i].StartPosition);
            Assert.AreEqual(28, lexems[i].EndPosition);
            Assert.AreEqual("a", lexems[i].Name);
            Assert.AreEqual(LexemKind.Other, lexems[i].Kind);
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
        public void Parse_SQLFile()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\1.sql");
            var lexems = _syntaxAnalyzer.Parse(fileText).ToList();
            Assert.AreEqual(1020, lexems.Count);
        }
    }
}
