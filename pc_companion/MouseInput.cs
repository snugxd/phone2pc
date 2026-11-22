using System.ComponentModel;
using System.Runtime.InteropServices;

internal static class MouseInput
{
    private const uint InputMouse = 0;
    private const uint MouseEventMove = 0x0001;
    private static readonly int InputSize = Marshal.SizeOf<Input>();

    internal static void Move(int dx, int dy)
    {
        var input = new Input
        {
            Type = InputMouse,
            Mouse = new NativeMouseInput
            {
                Dx = dx,
                Dy = dy,
                Flags = MouseEventMove
            }
        };

        if (SendInput(1, ref input, InputSize) != 1)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "SendInput failed to inject the mouse movement.");
        }
    }

    // MOUSEINPUT is the largest member of Windows' INPUT union. Sequential
    // layout supplies the correct pointer alignment and size on x86 and x64.
    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public NativeMouseInput Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeMouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, ref Input input, int size);
}
