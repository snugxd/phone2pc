using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;

if (!OperatingSystem.IsWindows())
{
    Console.Error.WriteLine("This companion requires Windows.");
    return;
}

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cancellation.Cancel();
};

using var listener = new UdpClient(new IPEndPoint(IPAddress.Any, 45454));
var senders = new Dictionary<IPEndPoint, SenderState>();
var scrollSenders = new Dictionary<IPEndPoint, ScrollState>();
var buttons = new ButtonReceiver();
EventHandler releaseOnExit = (_, _) => buttons.ReleaseAll();
AppDomain.CurrentDomain.ProcessExit += releaseOnExit;
long packetsReceived = 0;
long sequenceGaps = 0;
long scrollPacketsReceived = 0;
long scrollSequenceGaps = 0;
Task statistics = PrintStatisticsAsync();
Task buttonSafety = RunButtonSafetyAsync();
Console.WriteLine("Listening on UDP 45454");

try
{
    while (!cancellation.IsCancellationRequested)
    {
        UdpReceiveResult packet = await listener.ReceiveAsync(cancellation.Token);
        Interlocked.Increment(ref packetsReceived);
        byte[] data = packet.Buffer;
        if (data.Length == 6 && data[0] == 4)
        {
            buttons.Receive(packet.RemoteEndPoint,
                BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(1, 4)), data[5]);
            continue;
        }
        if (data.Length != 13)
            continue;
        if (data[0] == 2)
        {
            data[0] = 3;
            await listener.SendAsync(data, packet.RemoteEndPoint, cancellation.Token);
            continue;
        }
        if (data[0] == 5)
        {
            Interlocked.Increment(ref scrollPacketsReceived);
            uint scrollSequence = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(1, 4));
            int totalH = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(5, 4));
            int totalV = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(9, 4));
            var currentScroll = new ScrollState(scrollSequence, totalH, totalV);

            if (!scrollSenders.TryGetValue(packet.RemoteEndPoint, out ScrollState previousScroll))
            {
                scrollSenders[packet.RemoteEndPoint] = currentScroll;
                continue;
            }

            uint scrollAdvance = unchecked(scrollSequence - previousScroll.Sequence);
            if (scrollAdvance == 0 || scrollAdvance >= 0x80000000u)
                continue;

            Interlocked.Add(ref scrollSequenceGaps, (long)scrollAdvance - 1);
            int dH = (int)Math.Clamp((long)totalH - previousScroll.TotalH, -1200L, 1200L);
            int dV = (int)Math.Clamp((long)totalV - previousScroll.TotalV, -1200L, 1200L);
            scrollSenders[packet.RemoteEndPoint] = currentScroll;
            MouseInput.Scroll(dH, dV);
            continue;
        }
        if (data[0] != 1)
            continue;

        uint sequence = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(1, 4));
        int totalX = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(5, 4));
        int totalY = BinaryPrimitives.ReadInt32LittleEndian(data.AsSpan(9, 4));
        var current = new SenderState(sequence, totalX, totalY);

        if (!senders.TryGetValue(packet.RemoteEndPoint, out SenderState previous))
        {
            senders[packet.RemoteEndPoint] = current;
            continue;
        }

        // Forward distances below half the uint range are newer, including wraparound.
        uint advance = unchecked(sequence - previous.Sequence);
        if (advance == 0 || advance >= 0x80000000u)
            continue;

        Interlocked.Add(ref sequenceGaps, (long)advance - 1);
        // Widen before subtracting so large signed totals cannot overflow.
        int dx = (int)Math.Clamp((long)totalX - previous.TotalX, -300L, 300L);
        int dy = (int)Math.Clamp((long)totalY - previous.TotalY, -300L, 300L);
        senders[packet.RemoteEndPoint] = current;
        MouseInput.Move(dx, dy);
    }
}
catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
{
    // Ctrl+C cancels the pending receive.
}
finally
{
    cancellation.Cancel();
    try
    {
        await Task.WhenAll(statistics, buttonSafety);
    }
    finally
    {
        buttons.ReleaseAll();
        AppDomain.CurrentDomain.ProcessExit -= releaseOnExit;
    }
}

async Task RunButtonSafetyAsync()
{
    try
    {
        await buttons.RunTimeoutsAsync(cancellation.Token);
    }
    catch
    {
        // Do not leave the receiver running without its button-release watchdog.
        cancellation.Cancel();
        throw;
    }
}

async Task PrintStatisticsAsync()
{
    using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
    try
    {
        while (await timer.WaitForNextTickAsync(cancellation.Token))
        {
            long received = Interlocked.Exchange(ref packetsReceived, 0);
            long gaps = Interlocked.Exchange(ref sequenceGaps, 0);
            long scrollReceived = Interlocked.Exchange(ref scrollPacketsReceived, 0);
            long scrollGaps = Interlocked.Exchange(ref scrollSequenceGaps, 0);
            Console.WriteLine($"Packets received: {received}; sequence gaps: {gaps}; " +
                $"scroll packets: {scrollReceived}; scroll gaps: {scrollGaps}");
        }
    }
    catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
    {
        // Stop the statistics timer along with the receiver.
    }
}

readonly record struct SenderState(uint Sequence, int TotalX, int TotalY);
readonly record struct ScrollState(uint Sequence, int TotalH, int TotalV);
