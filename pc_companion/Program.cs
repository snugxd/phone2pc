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
long packetsReceived = 0;
long sequenceGaps = 0;
Task statistics = PrintStatisticsAsync();
Console.WriteLine("Listening on UDP 45454");

try
{
    while (!cancellation.IsCancellationRequested)
    {
        UdpReceiveResult packet = await listener.ReceiveAsync(cancellation.Token);
        Interlocked.Increment(ref packetsReceived);
        byte[] data = packet.Buffer;
        if (data.Length != 13)
            continue;
        if (data[0] == 2)
        {
            data[0] = 3;
            await listener.SendAsync(data, packet.RemoteEndPoint, cancellation.Token);
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
    await statistics;
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
            Console.WriteLine($"Packets received: {received}; sequence gaps: {gaps}");
        }
    }
    catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
    {
        // Stop the statistics timer along with the receiver.
    }
}

readonly record struct SenderState(uint Sequence, int TotalX, int TotalY);
