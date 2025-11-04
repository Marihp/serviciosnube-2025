// src/app/api/performHighServerLoad/route.ts
import { NextRequest, NextResponse } from 'next/server';
import os from 'node:os';
import crypto from 'node:crypto';
import fs from 'node:fs';

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const nCPU = os.cpus()?.length || 1;

  const seconds = Math.max(
    1,
    Math.min(120, Number(url.searchParams.get('duration') || 10)),
  );
  const workers = Math.max(
    1,
    Math.min(nCPU, Number(url.searchParams.get('workers') || 1)),
  );
  const memMB = Math.max(
    0,
    Math.min(512, Number(url.searchParams.get('memMB') || 0)),
  );
  const doIO = url.searchParams.get('io') === '1';

  const until = Date.now() + seconds * 1000;

  // Reserva memoria (opcional)
  const buffers: Buffer[] = [];
  if (memMB > 0) {
    const chunk = Buffer.alloc(1024 * 1024, 1);
    for (let i = 0; i < memMB; i++) buffers.push(Buffer.from(chunk));
  }

  // IO (opcional)
  const ioTask = async () => {
    if (!doIO) return;
    const p = '/tmp/stress.txt';
    while (Date.now() < until) {
      fs.appendFileSync(p, crypto.randomBytes(1024).toString('hex'));
      // lectura rápida
      fs.readFileSync(p);
      await new Promise((r) => setTimeout(r, 5));
    }
    try { fs.unlinkSync(p); } catch {}
  };

  // CPU: pbkdf2Sync bloqueante
  const cpuTask = () =>
    new Promise<void>((resolve) => {
      while (Date.now() < until) {
        crypto.pbkdf2Sync('x', 'y', 100_000, 64, 'sha512');
      }
      resolve();
    });

  const cpuTasks = Array.from({ length: workers }, cpuTask);

  await Promise.all([ioTask(), ...cpuTasks]);

  return NextResponse.json({
    ok: true,
    seconds,
    workers,
    memMB,
    io: !!doIO,
    host: os.hostname(),
  });
}
