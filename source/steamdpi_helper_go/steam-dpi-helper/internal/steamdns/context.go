// SPDX-License-Identifier: GPL-3.0-only
package steamdns

import (
	"context"
	"time"
)

func cleanupContext() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 15*time.Second)
}
