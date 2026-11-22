using System.ComponentModel;
using System.Runtime.InteropServices;

internal static class MouseInput
{
    private const uint InputMouse = 0;
    private const uint MouseEventMove = 0x0001;
    private const uint MouseEventLeftDown = 0x0002;
    private const uint MouseEventLeftUp = 0x0004;
    private const uint MouseEventRightDown = 0x0008;
    private const uint MouseEventRightUp = 0x0010;
    private const uint MouseEventMiddleDown = 0x0020;
    private const uint MouseEventMiddleUp = 0x0040;
    private const uint MouseEventWheel = 0x0800;
    private const uint MouseEventHorizontalWheel = 0x1000;
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

    internal static void SetButtons(byte previous, byte current)
    {
        int changed = previous ^ current;
        uint flags = 0;
        if ((changed & 1) != 0)
            flags |= (current & 1) != 0 ? MouseEventLeftDown : MouseEventLeftUp;
        if ((changed & 2) != 0)
            flags |= (current & 2) != 0 ? MouseEventRightDown : MouseEventRightUp;
        if ((changed & 4) != 0)
            flags |= (current & 4) != 0 ? MouseEventMiddleDown : MouseEventMiddleUp;
        if (flags == 0)
            return;

        var input = new Input
        {
            Type = InputMouse,
            Mouse = new NativeMouseInput { Flags = flags }
        };
        if (SendInput(1, ref input, InputSize) != 1)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "SendInput failed to inject the mouse button state.");
        }
    }

    internal static void Scroll(int horizontal, int vertical)
    {
        if (vertical != 0)
            SendWheel(vertical, MouseEventWheel, "vertical");
        if (horizontal != 0)
            SendWheel(horizontal, MouseEventHorizontalWheel, "horizontal");
    }

    private static void SendWheel(int delta, uint flag, string direction)
    {
        var input = new Input
        {
            Type = InputMouse,
            Mouse = new NativeMouseInput
            {
                MouseData = unchecked((uint)delta),
                Flags = flag
            }
        };
        if (SendInput(1, ref input, InputSize) != 1)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                $"SendInput failed to inject the {direction} mouse wheel movement.");
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
