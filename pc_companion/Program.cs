using System.Net;
using System.Net.Sockets;
using System.Text;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cancellation.Cancel();
};

using var listener = new UdpClient(new IPEndPoint(IPAddress.Any, 45454));
Console.WriteLine("Listening on UDP 45454");

try
{
    while (!cancellation.IsCancellationRequested)
    {
        UdpReceiveResult packet = await listener.ReceiveAsync(cancellation.Token);
        string contents = Encoding.UTF8.GetString(packet.Buffer);
        Console.WriteLine($"{DateTimeOffset.Now:O} {packet.RemoteEndPoint.Address} {contents}");
    }
}
catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
{
    // Ctrl+C cancels the pending receive so the socket can be disposed.
}
