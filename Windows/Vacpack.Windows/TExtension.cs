using System.Windows.Markup;
using Vacpack.Core;

namespace Vacpack.Windows;

/// <summary>XAML text in the interface language: <c>Text="{l:T 'Русский текст'}"</c> (see <see cref="Loc"/>).</summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TExtension(string text) : MarkupExtension
{
    public override object ProvideValue(IServiceProvider serviceProvider) => Loc.T(text);
}
