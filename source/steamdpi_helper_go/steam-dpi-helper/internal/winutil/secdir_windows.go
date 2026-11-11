package winutil

import (
	"errors"
	"fmt"
	"unsafe"

	"golang.org/x/sys/windows"
)

// AdminOnlySDDL grants full control to SYSTEM and Administrators only,
// with inheritance from the parent blocked (protected DACL).
const AdminOnlySDDL = "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"

// SecureDir creates dir if needed and replaces its DACL with
// AdminOnlySDDL, so programs running as a normal user can neither read
// nor replace what Ghostline (elevated) keeps there.
func SecureDir(dir string) error {
	// DCGaming: protect the directory from its first creation, and apply
	// ownership/DACL through a non-reparse, non-delete-sharing handle.
	sd, err := windows.SecurityDescriptorFromString("O:BAG:BA" + AdminOnlySDDL)
	if err != nil {
		return err
	}
	dacl, _, err := sd.DACL()
	if err != nil {
		return err
	}
	name, err := windows.UTF16PtrFromString(dir)
	if err != nil {
		return err
	}
	sa := windows.SecurityAttributes{Length: uint32(unsafe.Sizeof(windows.SecurityAttributes{})), SecurityDescriptor: sd}
	if err := windows.CreateDirectory(name, &sa); err != nil && !errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return err
	}
	handle, err := windows.CreateFile(name, windows.READ_CONTROL|windows.WRITE_DAC|windows.WRITE_OWNER|windows.FILE_READ_ATTRIBUTES,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING,
		windows.FILE_FLAG_BACKUP_SEMANTICS|windows.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		return err
	}
	defer windows.CloseHandle(handle)
	var info windows.ByHandleFileInformation
	if err = windows.GetFileInformationByHandle(handle, &info); err != nil {
		return err
	}
	if info.FileAttributes&windows.FILE_ATTRIBUTE_REPARSE_POINT != 0 || info.FileAttributes&windows.FILE_ATTRIBUTE_DIRECTORY == 0 {
		return errors.New("untrusted runtime directory")
	}
	current, err := windows.GetSecurityInfo(handle, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION)
	if err != nil {
		return err
	}
	owner, _, err := current.Owner()
	if err != nil {
		return err
	}
	admin, err := windows.CreateWellKnownSid(windows.WinBuiltinAdministratorsSid)
	if err != nil {
		return err
	}
	system, err := windows.CreateWellKnownSid(windows.WinLocalSystemSid)
	if err != nil {
		return err
	}
	if !owner.Equals(admin) && !owner.Equals(system) {
		return errors.New("untrusted runtime owner")
	}
	err = windows.SetSecurityInfo(handle, windows.SE_FILE_OBJECT,
		windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION|windows.OWNER_SECURITY_INFORMATION, admin, nil, dacl, nil)
	if err != nil {
		return fmt.Errorf("secure %s: %w", dir, err)
	}
	return nil
}

// OwnedByAdmins reports whether path is owned by Administrators or SYSTEM.
// Files Ghostline writes while elevated are; a file planted by a normal
// user is not.
func OwnedByAdmins(path string) (bool, error) {
	sd, err := windows.GetNamedSecurityInfo(path, windows.SE_FILE_OBJECT, windows.OWNER_SECURITY_INFORMATION)
	if err != nil {
		return false, err
	}
	owner, _, err := sd.Owner()
	if err != nil {
		return false, err
	}
	for _, w := range []windows.WELL_KNOWN_SID_TYPE{windows.WinBuiltinAdministratorsSid, windows.WinLocalSystemSid} {
		sid, err := windows.CreateWellKnownSid(w)
		if err == nil && owner.Equals(sid) {
			return true, nil
		}
	}
	return false, nil
}
