using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using Microsoft.Windows.Widgets;
using Microsoft.Windows.Widgets.Providers;

namespace CostWidgetProvider;

[ComVisible(true)]
[ComDefaultInterface(typeof(IWidgetProvider))]
[Guid("6136713A-5359-4967-805F-3453FB1A076F")]
public sealed class WidgetProvider : IWidgetProvider
{
    private sealed class WidgetState
    {
        public WidgetSize Size { get; set; } = WidgetSize.Medium;
        public bool IsActivated { get; set; }
    }

    private static readonly ConcurrentDictionary<string, WidgetState> RunningWidgets = new();
    private static readonly ManualResetEvent EmptyWidgetListEvent = new(false);
    private static readonly object TimerGate = new();
    private static Timer? _refreshTimer;
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(60);
    private static int _recovered;
    private static DateTimeOffset _lastActivity = DateTimeOffset.Now;

    public WidgetProvider()
    {
        if (Interlocked.Exchange(ref _recovered, 1) == 0)
        {
            RecoverRunningWidgets();
        }
    }

    public static ManualResetEvent GetEmptyWidgetListEvent() => EmptyWidgetListEvent;

    // Exiting with zero widgets before the first CreateWidget arrives would fail
    // the pending COM activation, hence the grace period since the last activity.
    public static bool ShouldExitWhenIdle() =>
        RunningWidgets.IsEmpty && DateTimeOffset.Now - _lastActivity > TimeSpan.FromMinutes(2);

    private static void RecoverRunningWidgets()
    {
        try
        {
            var infos = WidgetManager.GetDefault().GetWidgetInfos();
            foreach (var info in infos ?? [])
            {
                RunningWidgets.TryAdd(info.WidgetContext.Id, new WidgetState
                {
                    Size = info.WidgetContext.Size,
                });
            }
            Logger.Log($"recovered {RunningWidgets.Count} widget(s)");
        }
        catch (Exception ex)
        {
            Logger.Log($"RecoverRunningWidgets failed: {ex.Message}");
        }
    }

    public void CreateWidget(WidgetContext widgetContext)
    {
        Logger.Log($"CreateWidget {widgetContext.Id} size={widgetContext.Size}");
        _lastActivity = DateTimeOffset.Now;
        RunningWidgets[widgetContext.Id] = new WidgetState { Size = widgetContext.Size };
        EmptyWidgetListEvent.Reset();
        _ = RenderWidgetAsync(widgetContext.Id, force: false);
    }

    public void DeleteWidget(string widgetId, string customState)
    {
        Logger.Log($"DeleteWidget {widgetId}");
        RunningWidgets.TryRemove(widgetId, out _);
        if (RunningWidgets.IsEmpty)
        {
            StopTimer();
            EmptyWidgetListEvent.Set();
        }
    }

    public void OnActionInvoked(WidgetActionInvokedArgs actionInvokedArgs)
    {
        Logger.Log($"OnActionInvoked verb={actionInvokedArgs.Verb}");
        if (actionInvokedArgs.Verb == "refresh")
        {
            _ = RenderWidgetAsync(actionInvokedArgs.WidgetContext.Id, force: true);
        }
    }

    public void OnWidgetContextChanged(WidgetContextChangedArgs contextChangedArgs)
    {
        var context = contextChangedArgs.WidgetContext;
        Logger.Log($"OnWidgetContextChanged {context.Id} size={context.Size}");
        if (RunningWidgets.TryGetValue(context.Id, out var state))
        {
            state.Size = context.Size;
        }
        _ = RenderWidgetAsync(context.Id, force: false);
    }

    public void Activate(WidgetContext widgetContext)
    {
        Logger.Log($"Activate {widgetContext.Id}");
        _lastActivity = DateTimeOffset.Now;
        if (RunningWidgets.TryGetValue(widgetContext.Id, out var state))
        {
            state.IsActivated = true;
            state.Size = widgetContext.Size;
        }
        _ = RenderWidgetAsync(widgetContext.Id, force: false);
        EnsureTimer();
    }

    public void Deactivate(string widgetId)
    {
        Logger.Log($"Deactivate {widgetId}");
        if (RunningWidgets.TryGetValue(widgetId, out var state))
        {
            state.IsActivated = false;
        }
        if (!RunningWidgets.Values.Any(s => s.IsActivated))
        {
            StopTimer();
        }
    }

    private static void EnsureTimer()
    {
        lock (TimerGate)
        {
            _refreshTimer ??= new Timer(_ => RefreshActivatedWidgets(), null, RefreshInterval, RefreshInterval);
        }
    }

    private static void StopTimer()
    {
        lock (TimerGate)
        {
            _refreshTimer?.Dispose();
            _refreshTimer = null;
        }
    }

    private static void RefreshActivatedWidgets()
    {
        foreach (var (id, state) in RunningWidgets)
        {
            if (state.IsActivated)
            {
                _ = RenderWidgetAsync(id, force: false);
            }
        }
    }

    private static async Task RenderWidgetAsync(string widgetId, bool force)
    {
        try
        {
            if (!RunningWidgets.TryGetValue(widgetId, out var state))
            {
                return;
            }

            var data = await UsageService.GetCardDataJsonAsync(force);
            var template = LoadTemplate(state.Size);

            var options = new WidgetUpdateRequestOptions(widgetId)
            {
                Template = template,
                Data = data,
            };
            WidgetManager.GetDefault().UpdateWidget(options);
        }
        catch (Exception ex)
        {
            Logger.Log($"RenderWidget {widgetId} failed: {ex}");
        }
    }

    private static readonly ConcurrentDictionary<string, string> TemplateCache = new();

    private static string LoadTemplate(WidgetSize size)
    {
        var name = size switch
        {
            WidgetSize.Small => "small.json",
            WidgetSize.Large => "large.json",
            _ => "full.json",
        };

        return TemplateCache.GetOrAdd(name, n =>
            File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Templates", n)));
    }
}
