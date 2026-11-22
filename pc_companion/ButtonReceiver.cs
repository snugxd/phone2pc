using System.Diagnostics;
using System.Net;

internal sealed class ButtonReceiver
{
    private readonly object sync = new();
    private readonly Dictionary<IPEndPoint, ButtonState> senders = new();

    internal void Receive(IPEndPoint sender, uint sequence, byte mask)
    {
        lock (sync)
        {
            if (senders.TryGetValue(sender, out ButtonState previous))
            {
                uint advance = unchecked(sequence - previous.Sequence);
                if (advance == 0 || advance >= 0x80000000u)
                    return;
            }

            // Only the three defined button bits affect Windows input.
            mask &= 7;
            MouseInput.SetButtons(previous.Mask, mask);
            senders[sender] = new ButtonState(sequence, mask, Stopwatch.GetTimestamp());
        }
    }

    internal async Task RunTimeoutsAsync(CancellationToken cancellation)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(25));
        try
        {
            while (await timer.WaitForNextTickAsync(cancellation))
            {
                lock (sync)
                {
                    long now = Stopwatch.GetTimestamp();
                    foreach (var (sender, state) in senders)
                    {
                        if (state.Mask != 0 &&
                            Stopwatch.GetElapsedTime(state.LastAccepted, now) >= TimeSpan.FromSeconds(1))
                        {
                            MouseInput.SetButtons(state.Mask, 0);
                            // Keep the accepted sequence after releasing, so stale packets stay stale.
                            senders[sender] = state with { Mask = 0 };
                        }
                    }
                }
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // Shutdown releases all remaining held buttons in Program's finally block.
        }
    }

    internal void ReleaseAll()
    {
        lock (sync)
        {
            foreach (var (sender, state) in senders)
            {
                if (state.Mask == 0)
                    continue;
                try
                {
                    MouseInput.SetButtons(state.Mask, 0);
                    senders[sender] = state with { Mask = 0 };
                }
                catch (System.ComponentModel.Win32Exception error)
                {
                    // Still attempt to release every other sender if Windows rejects one.
                    Console.Error.WriteLine($"Could not release buttons for {sender}: {error.Message}");
                }
            }
        }
    }

    private readonly record struct ButtonState(uint Sequence, byte Mask, long LastAccepted);
}
