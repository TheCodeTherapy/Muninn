#version 100
precision highp float;
precision highp sampler2D;

uniform sampler2D originalTexture;
uniform sampler2D bloomTexture;
uniform float bloomStrength;
uniform float exposure;

varying vec2 fragTexCoord;

void main() {
  vec4 original = texture2D(originalTexture, fragTexCoord);
  vec4 bloom = texture2D(bloomTexture, fragTexCoord);

  // additive blending with strength control
  vec3 result = original.rgb + bloom.rgb * bloomStrength;

  // optional exposure/tone mapping
  result = vec3(1.0) - exp(-result * exposure);

  gl_FragColor = vec4(result, original.a);
}
