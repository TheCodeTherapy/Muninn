#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D inputTexture;
uniform float threshold;
uniform float intensity;

in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
  vec4 color = texture(inputTexture, fragTexCoord);

  // calculate luminance
  float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));

  // apply threshold with smooth falloff
  float brightnessFactor = max(0.0, luminance - threshold) / (1.0 - threshold);
  brightnessFactor = smoothstep(0.0, 1.0, brightnessFactor);

  // output bright areas only
  fragColor = vec4(color.rgb * brightnessFactor * intensity, color.a);
}
