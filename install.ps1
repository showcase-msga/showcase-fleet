# Moved, 23 Nov 2026: Showcase Fleet's installer is now fleet/install.ps1. This forwarder keeps install links made
# before the move working until their codes expire (30 Nov 2026), then it is removed. The one-time $code carries on.
irm 'https://raw.githubusercontent.com/showcase-msga/showcase-fleet/main/fleet/install.ps1' | iex
