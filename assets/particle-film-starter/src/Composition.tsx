import { AbsoluteFill, Composition } from "remotion";
import { DURATION_IN_FRAMES, FPS, HEIGHT, WIDTH } from "./config";
import { ParticleStage } from "./ParticleStage";

/**
 * 《天元：宇宙起点》 — TIANYUAN, ORIGIN OF THE UNIVERSE
 *
 * 1080x1920 / 9:16 / 60 FPS / 60 s.
 * 100% procedural: particles, motion, camera, light and shaders only.
 */
export const TianyuanOrigin: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      <ParticleStage />
    </AbsoluteFill>
  );
};

export const TianyuanOriginComposition: React.FC = () => {
  return (
    <Composition
      id="TianyuanOrigin"
      component={TianyuanOrigin}
      durationInFrames={DURATION_IN_FRAMES}
      fps={FPS}
      width={WIDTH}
      height={HEIGHT}
    />
  );
};
