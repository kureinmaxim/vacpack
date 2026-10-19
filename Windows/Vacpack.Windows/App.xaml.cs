using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Vacpack.Windows;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var window = new MainWindow();
        MainWindow = window;
        if (e.Args.Length >= 2 && e.Args[0] == "--snapshot")
        {
            try
            {
                window.ShowActivated = false;
                window.ShowInTaskbar = false;
                var arguments = e.Args.Skip(2).ToList();
                var compress = arguments.Remove("--compress");
                var sizeArgument = arguments.FirstOrDefault(argument => argument.StartsWith("--size=", StringComparison.Ordinal));
                if (sizeArgument is not null)
                {
                    var dimensions = sizeArgument[7..].Split('x');
                    if (dimensions.Length != 2 || !int.TryParse(dimensions[0], out var widthValue) || !int.TryParse(dimensions[1], out var heightValue)
                        || widthValue < window.MinWidth || heightValue < window.MinHeight) throw new ArgumentException("Invalid snapshot size.");
                    window.Width = widthValue; window.Height = heightValue;
                    arguments.Remove(sizeArgument);
                }
                window.Show();
                window.AddPaths(arguments);
                if (compress) await window.CompressAsync();
                await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
                var content = (FrameworkElement)window.Content;
                content.UpdateLayout();
                var width = content.ActualWidth + content.Margin.Left + content.Margin.Right;
                var height = content.ActualHeight + content.Margin.Top + content.Margin.Bottom;
                var drawing = new DrawingVisual();
                using (var context = drawing.RenderOpen())
                {
                    context.DrawRectangle(window.Background, null, new Rect(0, 0, width, height));
                    context.DrawRectangle(new VisualBrush(content), null,
                        new Rect(content.Margin.Left, content.Margin.Top, content.ActualWidth, content.ActualHeight));
                }
                var bitmap = new RenderTargetBitmap((int)width, (int)height, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(drawing);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file = File.Create(Path.GetFullPath(e.Args[1]));
                encoder.Save(file);
                Shutdown(0);
            }
            catch (Exception exception)
            {
                File.WriteAllText(Path.GetFullPath(e.Args[1]) + ".error.txt", exception.ToString());
                Shutdown(1);
            }
            return;
        }
        window.Show();
        window.AddPaths(e.Args);
    }
}
