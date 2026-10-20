import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // "standalone" for production server deployment
  // "export" for Tauri desktop build (static HTML/JS/CSS bundle)
  output: process.env.BUILD_MODE === "tauri" ? "export" : "standalone",
  /* config options here */
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,
};

export default nextConfig;
