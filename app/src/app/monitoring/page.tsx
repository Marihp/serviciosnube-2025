'use client'
import { useEffect, useState } from 'react';

type MonResp = {
  now: string;
  alb: {
    base: string;
    host: string;
    ips: string[];
    status: number;
    latency_ms: number | null;
    error: string | null;
  };
  instance: {
    instanceId: string | null;
    availabilityZone: string | null;
    localIp: string | null;
    hostname: string;
    containerIps: string[];
  };
  preview: string;
  requestHeaders: Record<string, string>;
};

export default function Monitoring() {
  const [data, setData] = useState<MonResp | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);

  useEffect(() => {
    let alive = true;

    async function tick() {
      try {
        const res = await fetch(`/api/monitoring?ts=${Date.now()}`, {
          cache: 'no-store',
          headers: { 'Cache-Control': 'no-cache' },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const j = (await res.json()) as MonResp;
        if (!alive) return;
        setData(j);
        setErr(null);
        setUpdatedAt(new Date());
      } catch (e: any) {
        if (!alive) return;
        setErr(String(e?.message || e));
      }
    }

    tick();
    const id = setInterval(tick, 1000);
    return () => { alive = false; clearInterval(id); };
  }, []);

  const statusColor =
    data?.alb.status && data.alb.status >= 200 && data.alb.status < 400
      ? '#10b981' // green
      : '#ef4444'; // red

  return (
    <main style={{ padding: 16, maxWidth: 1100, margin: '0 auto', fontFamily: 'ui-sans-serif, system-ui' }}>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 12 }}>Monitoring (ALB & EC2)</h1>

      <section style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))' }}>
        {/* ALB */}
        <div style={{ border: '1px solid #e5e7eb', borderRadius: 12, padding: 12 }}>
          <div style={{ fontWeight: 600, marginBottom: 8 }}>Application Load Balancer</div>
          <div><b>Base:</b> {data?.alb.base || '—'}</div>
          <div><b>Host:</b> {data?.alb.host || '—'}</div>
          <div><b>IPs:</b> {data?.alb.ips?.join(', ') || '—'}</div>
          <div><b>HTTP Status:</b> <span style={{ color: statusColor }}>{data?.alb.status ?? '—'}</span></div>
          <div><b>Latency:</b> {data?.alb.latency_ms != null ? `${data.alb.latency_ms} ms` : '—'}</div>
          {data?.alb.error && <div style={{ color: '#ef4444' }}><b>Error:</b> {data.alb.error}</div>}
        </div>

        {/* EC2 / Contenedor */}
        <div style={{ border: '1px solid #e5e7eb', borderRadius: 12, padding: 12 }}>
          <div style={{ fontWeight: 600, marginBottom: 8 }}>EC2 Instance</div>
          <div><b>InstanceId:</b> {data?.instance.instanceId || '—'}</div>
          <div><b>AZ:</b> {data?.instance.availabilityZone || '—'}</div>
          <div><b>Local IP:</b> {data?.instance.localIp || '—'}</div>
          <div><b>Container Hostname:</b> {data?.instance.hostname || '—'}</div>
          <div><b>Container IPs:</b> {data?.instance.containerIps?.join(', ') || '—'}</div>
        </div>

        {/* Meta */}
        <div style={{ border: '1px solid #e5e7eb', borderRadius: 12, padding: 12 }}>
          <div style={{ fontWeight: 600, marginBottom: 8 }}>Meta</div>
          <div><b>Updated:</b> {updatedAt ? updatedAt.toLocaleTimeString() : '—'}</div>
          <div><b>Server Now:</b> {data?.now || '—'}</div>
          {err && <div style={{ color: '#ef4444' }}><b>Fetch error:</b> {err}</div>}
        </div>
      </section>

      <section style={{ marginTop: 16 }}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>HTML preview (ALB origin)</div>
        <textarea
          readOnly
          value={data?.preview || ''}
          style={{ width: '100%', minHeight: 260, border: '1px solid #e5e7eb', borderRadius: 12, padding: 10, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas' }}
        />
      </section>

      <section style={{ marginTop: 16 }}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>Request headers (to Next)</div>
        <pre style={{ overflowX: 'auto', background: '#0b1020', color: '#e5e7eb', padding: 12, borderRadius: 12 }}>
{JSON.stringify(data?.requestHeaders || {}, null, 2)}
        </pre>
      </section>
    </main>
  );
}
