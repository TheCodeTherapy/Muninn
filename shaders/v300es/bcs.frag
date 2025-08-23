#version 300 es

precision mediump float;

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D inputTexture;
uniform float brightness;  // -1.0 to 1.0, default 0.0
uniform float contrast;    // 0.0 to 2.0, default 1.0
uniform float saturation;  // 0.0 to 2.0, default 1.0

void main() {
  vec4 color = texture(inputTexture, fragTexCoord);
  color.rgb += brightness;
  color.rgb = (color.rgb - 0.5) * contrast + 0.5;
  float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
  color.rgb = mix(vec3(gray), color.rgb, saturation);
  color.rgb = clamp(color.rgb, 0.0, 1.0);
  finalColor = color;
}
