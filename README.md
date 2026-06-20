# Linux CUPS and Print Service Diagnostics Toolkit

A read-only Bash toolkit for diagnosing CUPS services, printer queues, jobs, drivers, devices, permissions, and network printer connectivity.

## Usage

```bash
chmod +x src/linux_cups_diagnostics.sh
sudo ./src/linux_cups_diagnostics.sh --printer-host 192.168.1.217 --port 9100
```

## Checks performed

- CUPS service state and recent events
- Printers, queues, jobs, devices, drivers, and PPDs
- cupsd configuration and access permissions
- Optional ping, IPP, and raw-print-port tests
- Text, CSV, and JSON reports

## Safety

The script never adds, removes, pauses, resumes, enables, disables, or modifies printers and jobs.

## Author

Dewald Pretorius — L2 IT Support Engineer
