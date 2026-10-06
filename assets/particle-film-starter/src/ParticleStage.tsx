import { AbsoluteFill, continueRender, delayRender, useCurrentFrame, useVideoConfig } from "remotion";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { PARTICLE_COUNT } from "./config";
import { ParticleEngine } from "./particles/engine";
import { sampleGlyphTargets } from "./particles/glyph";
import { computeFrameState } from "./timeline";

/**
 * The whole film lives on one canvas.
 *
 * There is no <Sequence>, no scene cut and no DOM element per particle: the
 * frame number is converted into a camera state and a pair of target
 * distributions, and the GPU does the rest.
 */
export const ParticleStage: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<ParticleEngine | null>(null);
  const [handle] = useState(() => delayRender("tianyuan-particle-init"));
  const [ready, setReady] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const boot = async () => {
      try {
        const canvas = canvasRef.current;
        if (!canvas) {
          throw new Error("particle canvas was not mounted");
        }
        const targets = await sampleGlyphTargets();
        if (cancelled) {
          return;
        }
        const engine = new ParticleEngine(canvas, PARTICLE_COUNT);
        engine.setGlyph(targets);
        engineRef.current = engine;
        setReady(true);
      } catch (err) {
        setFailure(err instanceof Error ? err.message : String(err));
      } finally {
        continueRender(handle);
      }
    };
    boot();
    return () => {
      cancelled = true;
      engineRef.current?.dispose();
      engineRef.current = null;
    };
  }, [handle]);

  useLayoutEffect(() => {
    if (!ready) {
      return;
    }
    engineRef.current?.render(computeFrameState(frame / fps), width, height);
  }, [ready, frame, fps, width, height]);

  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      <canvas
        ref={canvasRef}
        width={width}
        height={height}
        style={{
          display: "block",
          width: "100%",
          height: "100%",
        }}
      />
      {failure ? (
        <AbsoluteFill
          style={{
            alignItems: "center",
            backgroundColor: "rgba(0,0,0,0.85)",
            color: "#ff8080",
            display: "flex",
            fontFamily: "monospace",
            fontSize: 28,
            justifyContent: "center",
            padding: 60,
            textAlign: "center",
          }}
        >
          {failure}
        </AbsoluteFill>
      ) : null}
    </AbsoluteFill>
  );
};
