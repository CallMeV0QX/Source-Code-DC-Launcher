package zapret2_test

import (
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"testing"

	zapret2 "github.com/hashcott/ghostline/assets"
	pins "github.com/hashcott/ghostline/internal/dpi/zapret2"
)

// This test binary embeds winws2 and WinDivert; Smart App Control or
// Defender may refuse to run it. CI runs it on GitHub's Windows runners.
func TestEmbeddedFilesMatchPinnedHashes(t *testing.T) {
	for name, want := range pins.Pinned {
		b, err := fs.ReadFile(zapret2.FS, name)
		if err != nil {
			t.Fatal(err)
		}
		h := sha256.Sum256(b)
		if want != hex.EncodeToString(h[:]) {
			t.Fatalf("runtime mismatch: %s", name)
		}
	}
}
