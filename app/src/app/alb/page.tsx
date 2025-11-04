// src/app/alb/page.tsx (la tuya, con una mínima mejora)
'use client'
import { useState, useEffect } from 'react';

const LoadBalancerTestPage: React.FC = () => {
  const [lastUpdated, setLastUpdated] = useState(new Date());
  const [htmlContent, setHtmlContent] = useState<string>('Cargando…');

  useEffect(() => {
    let isMounted = true;

    const fetchHtml = async () => {
      try {
        const res = await fetch(`/proxy/albinfo?nocache=${Date.now()}`, {
          headers: { 'Cache-Control': 'no-cache', 'Pragma': 'no-cache', 'Expires': '0' },
        });
        if (isMounted) {
          if (res.ok) {
            const text = await res.text();
            setHtmlContent(text);
          } else {
            setHtmlContent(`<pre>HTTP ${res.status}</pre>`);
          }
          setLastUpdated(new Date());
        }
      } catch (e: any) {
        if (isMounted) setHtmlContent(`<pre>Error: ${e?.message || e}</pre>`);
      }
    };

    fetchHtml();
    const id = setInterval(fetchHtml, 1000);
    return () => { isMounted = false; clearInterval(id); };
  }, []);

  return (
    <section>
      <div style={{ textAlign: 'center', marginTop: 12 }}>
        Última actualización: {lastUpdated.toLocaleTimeString()}
      </div>
      <div
        style={{ width: '100%', minHeight: 220, border: '1px solid #ddd', marginTop: 10 }}
        dangerouslySetInnerHTML={{ __html: htmlContent }}
        suppressHydrationWarning
      />
    </section>
  );
};

export default LoadBalancerTestPage;
