using System;
using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using TSQLFormatter.Model;

namespace TSQLFormatter.Test.Model
{
    [TestClass]
    public class FormatterTest
    {
        private Formatter _formatter;

        [TestInitialize]
        public void Init()
        {
            _formatter = new Formatter();
        }

        [TestMethod]
        public void GetFormattedText_OneWord()
        {
            var text = "select";
            var expected = "SELECT";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_Query()
        {
            var text = "select * from MyTable";
            var expected = "SELECT * FROM [MyTable]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryTempTable()
        {
            var text = "select * from #TempTable";
            var expected = "SELECT * FROM [#TempTable]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithWhere()
        {
            var text = "select * from Products where a = 1";
            var expected = "SELECT * FROM [Products] WHERE [a] = 1";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithJoin()
        {
            var text = @"
select *
from Products
join NewProducts on c1 = c2
";
            var expected = @"
SELECT *
FROM [Products]
JOIN [NewProducts] ON [c1] = [c2]
";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithUnescape()
        {
            var text = "select [group] from Products";
            var expected = "SELECT [group] FROM [Products]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithUnescape2()
        {
            var text = "select [group]from Products";
            var expected = "SELECT [group]FROM [Products]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_RemoveTailSpaces()
        {
            var text = "select    ";
            var expected = "SELECT";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_RemoveTailSpaces2()
        {
            var text = @"select    
*   
from  
MyTable";
            var expected = @"SELECT
*
FROM
[MyTable]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_RemoveTailSpaces3()
        {
            var text = @"select    
*   
from  
[Table]";
            var expected = @"SELECT
*
FROM
[Table]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_String()
        {
            var text = "'select [group] from Products'";
            var expected = "'select [group] from Products'";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_TabToSpaces()
        {
            var text = "select * \tfrom Products";
            var expected = "SELECT *     FROM [Products]";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithString()
        {
            var text = "select * from Products where Code in ('1', '2', '3')";
            var expected = "SELECT * FROM [Products] WHERE [Code] IN ('1', '2', '3')";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_SQLFile_1()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\1.sql");
            _formatter.GetFormattedText(fileText);
        }

        [TestMethod]
        public void GetFormattedText_SQLFile_2()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\2.sql");
            _formatter.GetFormattedText(fileText);
        }

        [TestMethod]
        public void GetFormattedText_SQLFile_3()
        {
            var fileText = File.ReadAllText("..\\..\\SQLFiles\\3.sql");
            _formatter.GetFormattedText(fileText);
        }
    }
}
