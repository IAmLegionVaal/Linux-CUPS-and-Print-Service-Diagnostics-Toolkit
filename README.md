# Linux CUPS and Print Service Diagnostics Toolkit

A Linux support toolkit for diagnosing CUPS and printer problems and applying selected guarded repairs.

## Diagnostic script

```bash
chmod +x src/linux_cups_diagnostics.sh
sudo ./src/linux_cups_diagnostics.sh --printer-host 192.168.1.217 --port 9100
```

## Repair script

```bash
chmod +x src/linux_cups_repair.sh
sudo ./src/linux_cups_repair.sh --restart-cups --dry-run
```

Examples:

```bash
sudo ./src/linux_cups_repair.sh --restart-cups
sudo ./src/linux_cups_repair.sh --printer OfficePrinter --enable-printer
sudo ./src/linux_cups_repair.sh --printer OfficePrinter --resume-printer
sudo ./src/linux_cups_repair.sh --printer OfficePrinter --purge-jobs
sudo ./src/linux_cups_repair.sh --cancel-job OfficePrinter-42
```

## What the repair does

- Restarts and verifies the installed CUPS service.
- Enables one selected configured printer queue.
- Makes one selected queue accept jobs and resume printing.
- Cancels one selected print job.
- Can cancel all jobs on one selected printer after additional confirmation.
- Captures service, printer and job state before and after repair.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

Cancelling print jobs cannot be undone. The tool does not create or delete printer queues, install drivers, modify PPD files or change printer addresses automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
