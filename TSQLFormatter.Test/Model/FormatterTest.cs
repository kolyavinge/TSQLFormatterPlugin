using System;
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
            var expected = "SELECT * FROM MyTable";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }

        [TestMethod]
        public void GetFormattedText_QueryWithWhere()
        {
            var text = "select * from Products where a = 1";
            var expected = "SELECT * FROM Products WHERE a = 1";
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
FROM Products
JOIN NewProducts ON c1 = c2
";
            var actual = _formatter.GetFormattedText(text);
            Assert.AreEqual(expected, actual);
        }
    }
}
