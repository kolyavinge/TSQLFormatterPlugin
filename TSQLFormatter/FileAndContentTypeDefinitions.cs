using Microsoft.VisualStudio.Utilities;
using System.ComponentModel.Composition;

namespace TSQLFormatter
{
    internal static class FileAndContentTypeDefinitions
    {
        [Export]
        [Name("tsql")]
        [BaseDefinition("text")]
        internal static ContentTypeDefinition hidingContentTypeDefinition;

        [Export]
        [ContentType("tsql")]
        [FileExtension(".sql")]
        internal static FileExtensionToContentTypeDefinition hiddenFileExtensionDefinition;
    }
}
