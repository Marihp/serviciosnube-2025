import { NextResponse } from 'next/server';
import os from 'os';
import dns from 'dns/promises';

export async function GET(request: Request) {
  const baseRaw = process.env.LOAD_BALANCER_URL || '';
  let base = baseRaw.trim();
  if (base && !/^https?:\/\//i.test(base)) base = `http://${base}`;

  // 1) Pingar ALB y medir latencia
  let albStatus = 0;
  let albLatencyMs: number | null = null;
  let albError: string | null = null;
  let preview = '';

  try {
    const started = Date.now();
    const r = await fetch(`${base}/?nocache=${Date.now()}`, {
      method: 'GET',
      cache: 'no-store',
      headers: {
        'Cache-Control': 'no-cache',
        Pragma: 'no-cache',
        Expires: '0',
      },
    });
    albStatus = r.status;
    const txt = await r.text();
    preview = txt.slice(0, 2000);
    albLatencyMs = Date.now() - started;
  } catch (e: any) {
    albError = String(e?.message || e);
  }

  // 2) Resolver DNS del ALB
  let albHost = '';
  let albIps: string[] = [];
  try {
    albHost = base ? new URL(base).hostname : '';
    if (albHost) albIps = await dns.resolve4(albHost);
  } catch {
    // silencioso
  }

  // 3) IMDSv2: instance-id, AZ e IP local (no requiere permisos IAM)
  async function imds(path: string) {
    try {
      const token = await fetch('http://169.254.169.254/latest/api/token', {
        method: 'PUT',
        headers: { 'X-aws-ec2-metadata-token-ttl-seconds': '21600' },
      }).then(r => r.text()).catch(() => null);

      const headers: Record<string, string> = {};
      if (token) headers['X-aws-ec2-metadata-token'] = token;

      const res = await fetch(`http://169.254.169.254/latest/meta-data/${path}`, {
        headers,
        cache: 'no-store',
      });
      if (!res.ok) return null;
      return await res.text();
    } catch {
      return null;
    }
  }

  const [instanceId, az, localIp] = await Promise.all([
    imds('instance-id'),
    imds('placement/availability-zone'),
    imds('local-ipv4'),
  ]);

  // 4) Info del contenedor / red local
  const nets = os.networkInterfaces() || {};
  const containerIps = Object.values(nets)
    .flat()
    .filter((n): n is NonNullable<typeof n>[number] => !!n)
    .map(n => n.address)
    .filter(Boolean);

  // 5) Algunos headers útiles de la request que llegó al Next (pasando por el ALB)
  const reqHeaders = Object.fromEntries(
    Array.from(new Headers(request.headers)).slice(0, 50)
  );

  return NextResponse.json({
    now: new Date().toISOString(),
    alb: {
      base,
      host: albHost,
      ips: albIps,
      status: albStatus,
      latency_ms: albLatencyMs,
      error: albError,
    },
    instance: {
      instanceId,
      availabilityZone: az,
      localIp,
      hostname: os.hostname(),
      containerIps,
    },
    preview,
    requestHeaders: reqHeaders,
  });
}
