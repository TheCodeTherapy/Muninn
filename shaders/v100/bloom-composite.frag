#version 100
precision highp float;
precision highp sampler2D;

uniform sampler2D originalTexture;
uniform sampler2D bloomTexture;
uniform float bloomStrength;
uniform float exposure;
uniform float radius;

varying vec2 fragTexCoord;

void main() {
  vec4 original = texture2D(originalTexture, fragTexCoord);
  vec4 bloom = texture2D(bloomTexture, fragTexCoord);

  // additive blending with strength control
  vec3 result = original.rgb + bloom.rgb * bloomStrength;

  // optional exposure/tone mapping
  result = vec3(1.0) - exp(-result * exposure);

  float bloomLuminance = dot(bloom.rgb, vec3(0.299, 0.587, 0.114));
  float expandedAlpha = mix(original.a, max(original.a, bloomLuminance), radius);

  gl_FragColor = vec4(result, clamp(expandedAlpha, 0.0, 1.0));
}
