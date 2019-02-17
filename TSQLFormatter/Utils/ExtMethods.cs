using EnvDTE;
using System;
using System.Collections.Generic;
using System.Linq;

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

    public static class SelectedItemsExt
    {
        public static IEnumerable<ProjectItem> GetSelectedProjectItems(this SelectedItems selectedItems)
        {
            Microsoft.VisualStudio.Shell.ThreadHelper.ThrowIfNotOnUIThread();
            for (int selectedItemIndex = 1; selectedItemIndex <= selectedItems.Count; selectedItemIndex++)
            {
                yield return selectedItems.Item(selectedItemIndex).ProjectItem;
            }
        }

        public static IEnumerable<string> GetSelectedFiles(this SelectedItems selectedItems)
        {
            Microsoft.VisualStudio.Shell.ThreadHelper.ThrowIfNotOnUIThread();
            for (int selectedItemIndex = 1; selectedItemIndex <= selectedItems.Count; selectedItemIndex++)
            {
                var selectedProjectItem = selectedItems.Item(selectedItemIndex).ProjectItem;
                for (short selectedProjectItemFileIndex = 1; selectedProjectItemFileIndex <= selectedProjectItem.FileCount; selectedProjectItemFileIndex++)
                {
                    yield return selectedProjectItem.FileNames[selectedProjectItemFileIndex];
                }
            }
        }
    }

    public static class TextDocumentExt
    {
        public static string GetText(this TextDocument textDocument)
        {
            Microsoft.VisualStudio.Shell.ThreadHelper.ThrowIfNotOnUIThread();
            return textDocument.CreateEditPoint(textDocument.StartPoint).GetText(textDocument.EndPoint);
        }

        public static void SetText(this TextDocument textDocument, string text)
        {
            Microsoft.VisualStudio.Shell.ThreadHelper.ThrowIfNotOnUIThread();
            textDocument.CreateEditPoint(textDocument.StartPoint).Delete(textDocument.EndPoint);
            textDocument.CreateEditPoint(textDocument.StartPoint).Insert(text);
        }
    }
}
