"use client";

import { useEffect, useRef, useState } from "react";
import WaveSurfer from "wavesurfer.js";
import { Button } from "@/components/ui/button";

export function Waveform({ url }: { url: string }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WaveSurfer | null>(null);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!containerRef.current) return;
    const ws = WaveSurfer.create({
      container: containerRef.current,
      url,
      height: 64,
      waveColor: "#94a3b8",
      progressColor: "#0ea5e9",
      cursorColor: "#0ea5e9",
    });
    ws.on("play", () => setPlaying(true));
    ws.on("pause", () => setPlaying(false));
    ws.on("finish", () => setPlaying(false));
    wsRef.current = ws;
    return () => {
      ws.destroy();
      wsRef.current = null;
    };
  }, [url]);

  return (
    <div className="space-y-2">
      <div ref={containerRef} className="rounded border bg-muted/30 p-2" />
      <Button type="button" variant="outline" onClick={() => wsRef.current?.playPause()}>
        {playing ? "Pause" : "Play"}
      </Button>
    </div>
  );
}
