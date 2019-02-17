using EnvDTE;
using Microsoft.VisualStudio.Shell;
using System.IO;
using System;
using System.ComponentModel.Design;
using Task = System.Threading.Tasks.Task;
using System.Collections.Generic;
using TSQLFormatter.Utils;
using System.Linq;

namespace TSQLFormatter.Command
{
    /// <summary>
    /// Command handler
    /// </summary>
    internal sealed class TSQLFormatCommand
    {
        /// <summary>
        /// Command ID.
        /// </summary>
        public const int CommandId = 0x0100;

        /// <summary>
        /// FileContextCommand ID.
        /// </summary>
        public const int FileContextCommandId = 0x0101;

        /// <summary>
        /// Command menu group (command set GUID).
        /// </summary>
        public static readonly Guid CommandSet = new Guid("09725bb6-8797-4306-98de-8b32342cea67");

        /// <summary>
        /// VS Package that provides this command, not null.
        /// </summary>
        private readonly AsyncPackage _package;

        /// <summary>
        /// Initializes a new instance of the <see cref="TSQLFormatCommand"/> class.
        /// Adds our command handlers for menu (commands must exist in the command table file)
        /// </summary>
        /// <param name="package">Owner package, not null.</param>
        /// <param name="commandService">Command service to add command to, not null.</param>
        private TSQLFormatCommand(AsyncPackage package, OleMenuCommandService commandService)
        {
            _package = package ?? throw new ArgumentNullException(nameof(package));
            commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));

            var menuCommandID = new CommandID(CommandSet, CommandId);
            var menuItem = new OleMenuCommand(Execute, menuCommandID);
            menuItem.BeforeQueryStatus += MenuItem_BeforeQueryStatus;
            commandService.AddCommand(menuItem);

            var fileContextMenuCommandID = new CommandID(CommandSet, FileContextCommandId);
            var fileContextMenuItem = new OleMenuCommand(FileContextExecute, fileContextMenuCommandID);
            fileContextMenuItem.BeforeQueryStatus += FileContextMenuItem_BeforeQueryStatus;
            commandService.AddCommand(fileContextMenuItem);
        }

        private HashSet<string> _availableExtensions = new HashSet<string>(StringComparer.InvariantCultureIgnoreCase) { ".cs", ".sql" };
        private void MenuItem_BeforeQueryStatus(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var menuItem = (OleMenuCommand)sender;
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            menuItem.Visible = dte.ActiveDocument != null && _availableExtensions.Contains(Path.GetExtension(dte.ActiveDocument.FullName));
        }

        private void FileContextMenuItem_BeforeQueryStatus(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var menuItem = (OleMenuCommand)sender;
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            var selectedFileExtensions = dte.SelectedItems.GetSelectedFiles().Select(f => Path.GetExtension(f)).Distinct().ToList();
            menuItem.Visible = selectedFileExtensions.Count == 1 && String.Equals(selectedFileExtensions.First(), ".sql", StringComparison.InvariantCultureIgnoreCase);
        }

        /// <summary>
        /// Gets the instance of the command.
        /// </summary>
        public static TSQLFormatCommand Instance { get; private set; }

        /// <summary>
        /// Gets the service provider from the owner package.
        /// </summary>
        private IAsyncServiceProvider ServiceProvider
        {
            get { return _package; }
        }

        /// <summary>
        /// Initializes the singleton instance of the command.
        /// </summary>
        /// <param name="package">Owner package, not null.</param>
        public static async Task InitializeAsync(AsyncPackage package)
        {
            // Switch to the main thread - the call to AddCommand in TSQLFormatCommand's constructor requires
            // the UI thread.
            await ThreadHelper.JoinableTaskFactory.SwitchToMainThreadAsync(package.DisposalToken);
            OleMenuCommandService commandService = await package.GetServiceAsync(typeof(IMenuCommandService)) as OleMenuCommandService;
            Instance = new TSQLFormatCommand(package, commandService);
        }

        /// <summary>
        /// This function is the callback used to execute the command when the menu item is clicked.
        /// See the constructor to see how the menu item is associated with this function using
        /// OleMenuCommandService service and MenuCommand class.
        /// </summary>
        /// <param name="sender">Event sender.</param>
        /// <param name="e">Event args.</param>
        private void Execute(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            if (dte.ActiveDocument == null) return;
            var activeDocument = (TextDocument)dte.ActiveDocument.Object();
            if (activeDocument == null) return;
            var formatter = new TSQLFormatter.Model.Formatter();
            if (String.IsNullOrWhiteSpace(activeDocument.Selection.Text))
            {
                var activeDocumentText = activeDocument.CreateEditPoint(activeDocument.StartPoint).GetText(activeDocument.EndPoint);
                var activeDocumentFormattedText = formatter.GetFormattedText(activeDocumentText);
                activeDocument.CreateEditPoint(activeDocument.StartPoint).Delete(activeDocument.EndPoint);
                activeDocument.CreateEditPoint(activeDocument.StartPoint).Insert(activeDocumentFormattedText);
            }
            else
            {
                var formattedText = formatter.GetFormattedText(activeDocument.Selection.Text);
                activeDocument.Selection.Delete();
                activeDocument.Selection.Insert(formattedText);
            }
        }

        private void FileContextExecute(object sender, EventArgs e)
        {
            ThreadHelper.ThrowIfNotOnUIThread();
            var formatter = new TSQLFormatter.Model.Formatter();
            var dte = (DTE)Package.GetGlobalService(typeof(DTE));
            var selectedProjectItems = dte.SelectedItems.GetSelectedProjectItems().ToList();
            foreach (var selectedProjectItem in selectedProjectItems)
            {
                if (selectedProjectItem.Document != null)
                {
                    var textDocument = (TextDocument)selectedProjectItem.Document.Object();
                    var documentText = textDocument.CreateEditPoint(textDocument.StartPoint).GetText(textDocument.EndPoint);
                    var documentFormattedText = formatter.GetFormattedText(documentText);
                    textDocument.CreateEditPoint(textDocument.StartPoint).Delete(textDocument.EndPoint);
                    textDocument.CreateEditPoint(textDocument.StartPoint).Insert(documentFormattedText);
                }
                else
                {
                    var fileName = selectedProjectItem.FileNames[1];
                    var documentText = File.ReadAllText(fileName);
                    var documentFormattedText = formatter.GetFormattedText(documentText);
                    File.WriteAllText(fileName, documentFormattedText);
                }
            }
        }
    }
}
