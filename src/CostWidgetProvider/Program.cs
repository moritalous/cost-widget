using System.Runtime.InteropServices;

namespace CostWidgetProvider;

public static class Program
{
    [DllImport("ole32.dll")]
    private static extern int CoRegisterClassObject(
        [MarshalAs(UnmanagedType.LPStruct)] Guid rclsid,
        [MarshalAs(UnmanagedType.IUnknown)] object pUnk,
        uint dwClsContext,
        uint flags,
        out uint lpdwRegister);

    [DllImport("ole32.dll")]
    private static extern int CoRevokeClassObject(uint dwRegister);

    private const uint CLSCTX_LOCAL_SERVER = 0x4;
    private const uint REGCLS_MULTIPLEUSE = 1;

    public static void Main(string[] args)
    {
        Logger.Log($"Main invoked args=[{string.Join(" ", args)}]");
        if (!args.Any(a => a.Equals("-RegisterProcessAsComServer", StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        var hr = CoRegisterClassObject(
            typeof(WidgetProvider).GUID,
            new WidgetProviderFactory<WidgetProvider>(),
            CLSCTX_LOCAL_SERVER,
            REGCLS_MULTIPLEUSE,
            out var cookie);
        if (hr < 0)
        {
            Marshal.ThrowExceptionForHR(hr);
        }

        try
        {
            while (true)
            {
                if (WidgetProvider.GetEmptyWidgetListEvent().WaitOne(TimeSpan.FromSeconds(30)))
                {
                    break;
                }
                if (WidgetProvider.ShouldExitWhenIdle())
                {
                    Logger.Log("idle timeout, exiting");
                    break;
                }
            }
        }
        finally
        {
            _ = CoRevokeClassObject(cookie);
            Logger.Log("COM server exiting");
        }
    }
}
