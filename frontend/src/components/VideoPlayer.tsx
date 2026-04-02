import { useEffect, useRef, useCallback } from 'react';
import { ChromakeyRenderer } from '../shaders/chromakey';
import { CharacterState } from '../stateMachine';

type Props = {
  state: CharacterState;
  clips: Record<string, string[]>;
  loopStates: Set<string>;
  chromakeyThreshold: number;
  chromakeySmoothness: number;
  onClipEnd?: () => void;
  canvasWidth?: number;
  canvasHeight?: number;
};

export function VideoPlayer({
  state,
  clips,
  loopStates,
  chromakeyThreshold,
  chromakeySmoothness,
  onClipEnd,
  canvasWidth = 400,
  canvasHeight = 400,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const rendererRef = useRef<ChromakeyRenderer | null>(null);

  // 初始化 WebGL renderer
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const renderer = new ChromakeyRenderer(canvas);
    rendererRef.current = renderer;

    const resize = () => {
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.clientWidth * dpr;
      const h = canvas.clientHeight * dpr;
      renderer.resize(w, h);
    };
    resize();
    window.addEventListener('resize', resize);
    renderer.start();

    return () => {
      window.removeEventListener('resize', resize);
      renderer.destroy();
      rendererRef.current = null;
    };
  }, []);

  // 尺寸变化时更新 canvas
  useEffect(() => {
    const canvas = canvasRef.current;
    const renderer = rendererRef.current;
    if (canvas && renderer) {
      const dpr = window.devicePixelRatio || 1;
      renderer.resize(canvasWidth * dpr, canvasHeight * dpr);
    }
  }, [canvasWidth, canvasHeight]);

  // 绑定 video 到 renderer
  useEffect(() => {
    const video = videoRef.current;
    const renderer = rendererRef.current;
    if (video && renderer) {
      renderer.attachVideo(video);
    }
  }, []);

  // 更新 chromakey 参数
  useEffect(() => {
    rendererRef.current?.setThreshold(chromakeyThreshold);
  }, [chromakeyThreshold]);

  useEffect(() => {
    rendererRef.current?.setSmoothness(chromakeySmoothness);
  }, [chromakeySmoothness]);

  // 状态变化时切换视频
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const stateClips = clips[state];
    if (!stateClips || stateClips.length === 0) return;

    const clipPath = stateClips[Math.floor(Math.random() * stateClips.length)];
    // 绝对路径需要 file:// 协议才能在 WKWebView 中加载
    video.src = clipPath.startsWith('file://') ? clipPath : `file://${clipPath}`;
    video.loop = loopStates.has(state);
    video.play().catch(() => {});
  }, [state, clips, loopStates]);

  const handleEnded = useCallback(() => {
    onClipEnd?.();
  }, [onClipEnd]);

  return (
    <div className="video-player">
      <video
        ref={videoRef}
        style={{ display: 'none' }}
        muted
        playsInline
        onEnded={handleEnded}
      />
      <canvas
        ref={canvasRef}
        className="character-canvas"
        style={{ width: canvasWidth, height: canvasHeight }}
      />
    </div>
  );
}
