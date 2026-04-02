/**
 * WebGL Chromakey Shader
 * 将视频中的黑色背景过滤为透明，让角色浮在桌面上
 */

const vertexShaderSource = `
  attribute vec2 a_position;
  attribute vec2 a_texCoord;
  varying vec2 v_texCoord;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texCoord = a_texCoord;
  }
`;

const fragmentShaderSource = `
  precision mediump float;
  varying vec2 v_texCoord;
  uniform sampler2D u_texture;
  uniform float u_threshold;
  uniform float u_smoothness;

  void main() {
    vec4 color = texture2D(u_texture, v_texCoord);
    // 计算像素亮度 (luminance)
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    // 用 smoothstep 做平滑过渡，避免边缘生硬
    float alpha = smoothstep(u_threshold - u_smoothness, u_threshold + u_smoothness, luminance);
    gl_FragColor = vec4(color.rgb, alpha);
  }
`;

export class ChromakeyRenderer {
  private canvas: HTMLCanvasElement;
  private gl: WebGLRenderingContext;
  private program: WebGLProgram;
  private texture: WebGLTexture;
  private animationId: number = 0;
  private video: HTMLVideoElement | null = null;
  private thresholdLoc: WebGLUniformLocation;
  private smoothnessLoc: WebGLUniformLocation;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const gl = canvas.getContext('webgl', {
      alpha: true,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
    });
    if (!gl) throw new Error('WebGL not supported');
    this.gl = gl;

    // 编译 shader
    const vs = this.compileShader(gl.VERTEX_SHADER, vertexShaderSource);
    const fs = this.compileShader(gl.FRAGMENT_SHADER, fragmentShaderSource);
    this.program = this.createProgram(vs, fs);
    gl.useProgram(this.program);

    // 顶点数据：全屏四边形
    const positions = new Float32Array([
      -1, -1,  1, -1,  -1, 1,
      -1,  1,  1, -1,   1, 1,
    ]);
    const texCoords = new Float32Array([
      0, 1,  1, 1,  0, 0,
      0, 0,  1, 1,  1, 0,
    ]);

    this.bindAttribute('a_position', positions, 2);
    this.bindAttribute('a_texCoord', texCoords, 2);

    // 创建纹理
    this.texture = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    // uniform locations
    this.thresholdLoc = gl.getUniformLocation(this.program, 'u_threshold')!;
    this.smoothnessLoc = gl.getUniformLocation(this.program, 'u_smoothness')!;

    // 默认值
    gl.uniform1f(this.thresholdLoc, 0.3);
    gl.uniform1f(this.smoothnessLoc, 0.1);

    // 开启透明混合
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
  }

  setThreshold(value: number): void {
    this.gl.useProgram(this.program);
    this.gl.uniform1f(this.thresholdLoc, value);
  }

  setSmoothness(value: number): void {
    this.gl.useProgram(this.program);
    this.gl.uniform1f(this.smoothnessLoc, value);
  }

  attachVideo(video: HTMLVideoElement): void {
    this.video = video;
  }

  start(): void {
    this.stop();
    const render = () => {
      this.renderFrame();
      this.animationId = requestAnimationFrame(render);
    };
    this.animationId = requestAnimationFrame(render);
  }

  stop(): void {
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = 0;
    }
  }

  resize(width: number, height: number): void {
    this.canvas.width = width;
    this.canvas.height = height;
    this.gl.viewport(0, 0, width, height);
  }

  private renderFrame(): void {
    const { gl, video } = this;
    if (!video || video.readyState < 2) return;

    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);

    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }

  private compileShader(type: number, source: string): WebGLShader {
    const { gl } = this;
    const shader = gl.createShader(type)!;
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const info = gl.getShaderInfoLog(shader);
      gl.deleteShader(shader);
      throw new Error(`Shader compile error: ${info}`);
    }
    return shader;
  }

  private createProgram(vs: WebGLShader, fs: WebGLShader): WebGLProgram {
    const { gl } = this;
    const program = gl.createProgram()!;
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      const info = gl.getProgramInfoLog(program);
      throw new Error(`Program link error: ${info}`);
    }
    return program;
  }

  private bindAttribute(name: string, data: Float32Array, size: number): void {
    const { gl, program } = this;
    const loc = gl.getAttribLocation(program, name);
    const buf = gl.createBuffer()!;
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
  }

  destroy(): void {
    this.stop();
    this.gl.deleteTexture(this.texture);
    this.gl.deleteProgram(this.program);
  }
}
