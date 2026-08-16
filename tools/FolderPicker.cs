// atelier のフォルダ選択（新方式 IFileDialog / FOS_PICKFOLDERS の COM 呼び出し）
//
// 旧来の FolderBrowserDialog (SHBrowseForFolder) には「新規フォルダー作成→改名→即OK」で
// 改名前の古いパスを返す持病があり、Microsoft も新方式の使用を推奨しているため。
// setup.ps1 が Add-Type -Path で実行時にコンパイルする。追加インストールは不要。
using System;
using System.Runtime.InteropServices;

namespace Atelier {
    [ComImport]
    [Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    internal class FileOpenDialogRCW { }

    [ComImport]
    [Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileDialog {
        [PreserveSig] uint Show(IntPtr hwndParent);
        uint SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        uint SetFileTypeIndex(uint iFileType);
        uint GetFileTypeIndex(out uint piFileType);
        uint Advise(IntPtr pfde, out uint pdwCookie);
        uint Unadvise(uint dwCookie);
        uint SetOptions(uint fos);
        uint GetOptions(out uint fos);
        uint SetDefaultFolder(IShellItem psi);
        uint SetFolder(IShellItem psi);
        uint GetFolder(out IShellItem ppsi);
        uint GetCurrentSelection(out IShellItem ppsi);
        uint SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        uint GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        uint SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        uint SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        uint SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        uint GetResult(out IShellItem ppsi);
        uint AddPlace(IShellItem psi, uint fdap);
        uint SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        uint Close(uint hr);
        uint SetClientGuid(ref Guid guid);
        uint ClearClientData();
        uint SetFilter(IntPtr pFilter);
    }

    [ComImport]
    [Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem {
        uint BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        uint GetParent(out IShellItem ppsi);
        uint GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        uint GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        uint Compare(IShellItem psi, uint hint, out int piOrder);
    }

    public static class FolderPicker {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath, IntPtr pbc, ref Guid riid,
            [MarshalAs(UnmanagedType.Interface)] out IShellItem ppv);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();

        // 戻り値: 選ばれたフォルダの絶対パス。キャンセル時は null
        public static string Pick(string title, string defaultPath) {
            IFileDialog dlg = (IFileDialog)(new FileOpenDialogRCW());
            uint options;
            dlg.GetOptions(out options);
            dlg.SetOptions(options | 0x20 | 0x40);   // FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM
            dlg.SetTitle(title);
            if (!string.IsNullOrEmpty(defaultPath) && System.IO.Directory.Exists(defaultPath)) {
                try {
                    Guid iid = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
                    IShellItem folder;
                    SHCreateItemFromParsingName(defaultPath, IntPtr.Zero, ref iid, out folder);
                    dlg.SetFolder(folder);
                } catch { }
            }
            if (dlg.Show(GetConsoleWindow()) != 0) { return null; }   // 0以外＝キャンセル等
            IShellItem result;
            dlg.GetResult(out result);
            string path;
            result.GetDisplayName(0x80058000, out path);   // SIGDN_FILESYSPATH
            return path;
        }
    }
}
