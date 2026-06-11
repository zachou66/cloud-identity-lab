# sample-logs/

`Start-Transcript` output from `Onboard-CloudUsers.ps1`. The idempotency proof — the
strongest Phase 2 artifact — is two runs of the **same** 5-row CSV:

- [ ] `run1-created.txt` — first run, every row `CREATED`
- [ ] `run2-skipped.txt` — second run, every row `SKIPPED`

Generate them with:

```powershell
.\Onboard-CloudUsers.ps1 -CsvPath .\users.csv -LogPath .\sample-logs\run1-created.txt
.\Onboard-CloudUsers.ps1 -CsvPath .\users.csv -LogPath .\sample-logs\run2-skipped.txt
```
