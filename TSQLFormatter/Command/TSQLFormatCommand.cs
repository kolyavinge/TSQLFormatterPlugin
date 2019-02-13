using EnvDTE;
using Microsoft.VisualStudio.Shell;
using System;
using System.ComponentModel.Design;
using Task = System.Threading.Tasks.Task;

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
            this._package = package ?? throw new ArgumentNullException(nameof(package));
            commandService = commandService ?? throw new ArgumentNullException(nameof(commandService));
            var menuCommandID = new CommandID(CommandSet, CommandId);
            var menuItem = new MenuCommand(Execute, menuCommandID);
            commandService.AddCommand(menuItem);
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
    }
}
