const LOAD_BALANCER_URL = process.env.LOAD_BALANCER_URL || 'https://info.cern.ch';


/** @type {import('next').NextConfig} */

const nextConfig = {

  async rewrites() {
    return [
      {
        source: '/proxy/:path*',
        destination: `${LOAD_BALANCER_URL}/:path*`,
      },
    ]
  },
}
module.exports = nextConfig

