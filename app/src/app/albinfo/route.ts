// src/app/albinfo/route.ts
import type { NextRequest } from 'next/server';

async function imds(path: string, token: string, timeoutMs = 500) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`http://169.254.169.254/latest/meta-data/${path}`, {
      headers: { 'X-aws-ec2-metadata-token': token },
      signal: ctrl.signal,
    });
    if (!r.ok) throw new Error(String(r.status));
    return await r.text();
  } catch {
    return 'n/a';
  } finally {
    clearTimeout(t);
  }
}

async function getToken(timeoutMs = 500) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch('http://169.254.169.254/latest/api/token', {
      method: 'PUT',
      headers: { 'X-aws-ec2-metadata-token-ttl-seconds': '21600' },
      signal: ctrl.signal,
    });
    if (!r.ok) throw new Error(String(r.status));
    return await r.text();
  } catch {
    return '';
  } finally {
    clearTimeout(t);
  }
}

export async function GET(_req: NextRequest) {
  const token = await getToken();
  const [iid, ip, az] = await Promise.all([
    token ? imds('instance-id', token) : 'n/a',
    token ? imds('local-ipv4', token) : 'n/a',
    token ? imds('placement/availability-zone', token) : 'n/a',
  ]);

  const now = new Date().toISOString();
  const html = `
    <div style="font:14px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, sans-serif;padding:16px">
      <h2 style="margin:0 0 8px">ALB Target</h2>
      <table style="border-collapse:collapse">
        <tr><td style="padding:4px 8px"><b>Instance ID</b></td><td>${iid}</td></tr>
        <tr><td style="padding:4px 8px"><b>AZ</b></td><td>${az}</td></tr>
        <tr><td style="padding:4px 8px"><b>Private IP</b></td><td>${ip}</td></tr>
        <tr><td style="padding:4px 8px"><b>Container</b></td><td>${process.env.HOSTNAME || 'n/a'}</td></tr>
        <tr><td style="padding:4px 8px"><b>Time</b></td><td>${now}</td></tr>
      </table>
    </div>`;
  return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}
