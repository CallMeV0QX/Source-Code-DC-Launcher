// SPDX-License-Identifier: GPL-3.0-only
package winutil

import (
	"errors"
	"golang.org/x/sys/windows"
	"unsafe"
)

// ResumeProcess resumes the primary thread of our suspended child only.
func ResumeProcess(pid uint32) error {
	snapshot, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPTHREAD, 0)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(snapshot)
	var thread windows.ThreadEntry32
	thread.Size = uint32(unsafe.Sizeof(thread))
	err = windows.Thread32First(snapshot, &thread)
	for err == nil {
		if thread.OwnerProcessID == pid {
			h, err := windows.OpenThread(windows.THREAD_SUSPEND_RESUME, false, thread.ThreadID)
			if err != nil {
				return err
			}
			defer windows.CloseHandle(h)
			_, err = windows.ResumeThread(h)
			return err
		}
		err = windows.Thread32Next(snapshot, &thread)
	}
	return errors.New("suspended child thread not found")
}
