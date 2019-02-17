using EnvDTE;
using Microsoft.VisualStudio.Shell;
using System;
using System.Collections.Generic;
using System.ComponentModel.Design;
using System.IO;
using System.Linq;
using TSQLFormatter.Utils;
using Task = System.Threading.Tasks.Task;

namespace TSQLFormatter.Command
{
    /// <summary>
    /// Command handler
    /// </summary>
    internal sealed class TSQLFormatCommand
    {
        /// <summary>
        /// ID команды для вызова из главного меню и контекстного меню документа
        /// </summary>
        public const int MenuCommandId = 0x0100;

        /// <summary>
        /// ID команды для вызова из контекстного меню файла
        /// </summary>
        public const int FileContextMenuCommandId = 0x0101;

        public static readonly Guid CommandSet = new Guid("09725bb6-8797-4306-98de-8b32342cea67");

        private readonly AsyncPackage _package;

        private TSQLFormatCommand(AsyncPackage package, OleMenuCommandService commandService)
        {
            _package = package ?? throw new ArgumentNullException(nameof(package));
            commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

            var menuCommandID = new CommandID(CommandSet, MenuCommandId);
            var menuItem = new OleMenuCommand(ExecuteFromMenu, menuCommandID);
            menuItem.BeforeQueryStatus += MenuItemBeforeQueryStatus;
            commandService.AddCommand(menuItem);

            var fileContextMenuCommandID = new CommandID(CommandSet, FileContextMenuCommandId);
            var fileContextMenuItem = new OleMenuCommand(ExecuteFromFileContext, fileContextMenuCommandID);
            fileContextMenuItem.BeforeQueryStatus += FileContextMenuItemBeforeQueryStatus;
            commandService.AddCommand(fileContextMenuItem);
        }

        private HashSet<string> _availableExtensions = new HashSet<string>(StringComparer.InvariantCultureIgnoreCase) { ".cs", ".sql" };
        private void MenuItemBeforeQueryStatus(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var menuItem = (OleMenuCommand)sender;
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            menuItem.Visible = dte.ActiveDocument != null && _availableExtensions.Contains(Path.GetExtension(dte.ActiveDocument.FullName));
        }

        private void FileContextMenuItemBeforeQueryStatus(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var menuItem = (OleMenuCommand)sender;
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            var selectedFileExtensions = dte.SelectedItems.GetSelectedFiles().Select(f => Path.GetExtension(f)).Distinct().ToList();
            menuItem.Visible = selectedFileExtensions.Count == 1 && String.Equals(selectedFileExtensions.First(), ".sql", StringComparison.InvariantCultureIgnoreCase);
        }

        public static TSQLFormatCommand Instance { get; private set; }

        private IAsyncServiceProvider ServiceProvider { get { return _package; } }

        public static async Task InitializeAsync(AsyncPackage package)
        {
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);
            OleMenuCommandService commandService = await package.GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
            Instance = new TSQLFormatCommand(package, commandService);
        }

        private void ExecuteFromMenu(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            if (dte.ActiveDocument == null) return;
            var activeDocument = (TextDocument)dte.ActiveDocument.Object();
            if (activeDocument == null) return;
            var formatter = new TSQLFormatter.Model.Formatter();
            if (String.IsNullOrWhiteSpace(activeDocument.Selection.Text))
            {
                var formattedText = formatter.GetFormattedText(activeDocument.GetText());
                activeDocument.SetText(formattedText);
            }
            else
            {
                var formattedText = formatter.GetFormattedText(activeDocument.Selection.Text);
                activeDocument.Selection.Delete();
                activeDocument.Selection.Insert(formattedText);
            }
        }

        private void ExecuteFromFileContext(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var formatter = new TSQLFormatter.Model.Formatter();
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            var selectedProjectItems = dte.SelectedItems.GetSelectedProjectItems().ToList();
            foreach (var projectItem in selectedProjectItems)
            {
                if (projectItem.Document != null)
                {
                    var textDocument = (TextDocument)projectItem.Document.Object();
                    var formattedText = formatter.GetFormattedText(textDocument.GetText());
                    textDocument.SetText(formattedText);
                }
                else
                {
                    var fileName = projectItem.FileNames[1];
                    var fileText = File.ReadAllText(fileName);
                    var formattedText = formatter.GetFormattedText(fileText);
                    File.WriteAllText(fileName, formattedText);
                }
            }
        }
    }
}
