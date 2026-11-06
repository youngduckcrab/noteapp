// A Logger that keeps its entries (handler tests).

import type { LogFields, Logger } from "../../src/log.js";

export interface LogEntry {
  level: "info" | "warn" | "error";
  message: string;
  fields: LogFields;
}

export class MemoryLogger implements Logger {
  readonly entries: LogEntry[] = [];
  info(message: string, fields: LogFields): void {
    this.entries.push({ level: "info", message, fields });
  }
  warn(message: string, fields: LogFields): void {
    this.entries.push({ level: "warn", message, fields });
  }
  error(message: string, fields: LogFields): void {
    this.entries.push({ level: "error", message, fields });
  }
}
